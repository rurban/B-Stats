#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#ifdef I_SYS_TIME
#include <sys/time.h>
#endif

/* time tracking */
#ifdef WIN32
/* win32_gettimeofday has ~15 ms resolution on Win32, so use
 * QueryPerformanceCounter which has us or ns resolution depending on
 * motherboard and OS. Comment this out to use the old clock.
 */
#  define HAS_QPC
#endif

#ifdef HAS_CLOCK_GETTIME
/* http://www.freebsd.org/cgi/man.cgi?query=clock_gettime
 * http://webnews.giga.net.tw/article//mailing.freebsd.performance/710
 * http://sean.chittenden.org/news/2008/06/01/
 * Explanation of why gettimeofday() (and presumably CLOCK_REALTIME) may go backwards:
 * http://groups.google.com/group/comp.os.linux.development.apps/tree/browse_frm/thread/dc29071f2417f75f/ac44671fdb35f6db?rnum=1&_done=%2Fgroup%2Fcomp.os.linux.development.apps%2Fbrowse_frm%2Fthread%2Fdc29071f2417f75f%2Fc46264dba0863463%3Flnk%3Dst%26rnum%3D1%26#doc_776f910824bdbee8
 */
typedef struct timespec time_of_day_t;
#  define CLOCK_GETTIME(ts) clock_gettime(profile_clock, ts)
#  define TICKS_PER_SEC 10000000                /* 10 million - 100ns */
#  define get_time_of_day(into) CLOCK_GETTIME(&into)
#  define get_ticks_between(typ, s, e, ticks, overflow) STMT_START { \
    overflow = 0; \
    ticks = ((e.tv_sec - s.tv_sec) * TICKS_PER_SEC + (e.tv_nsec / (typ)100) - (s.tv_nsec / (typ)100)); \
} STMT_END

#else                                             /* !HAS_CLOCK_GETTIME */

#ifdef HAS_MACH_TIME

#include <mach/mach.h>
#include <mach/mach_time.h>
mach_timebase_info_data_t  our_timebase;
typedef uint64_t time_of_day_t;
#  define TICKS_PER_SEC 10000000                /* 10 million - 100ns */
#  define get_time_of_day(into) into = mach_absolute_time()
#  define get_ticks_between(typ, s, e, ticks, overflow) STMT_START { \
    overflow = 0; \
    if( our_timebase.denom == 0 ) mach_timebase_info(&our_timebase); \
    ticks = (e-s) * our_timebase.numer / our_timebase.denom / (typ)100; \
} STMT_END

#else                                             /* !HAS_MACH_TIME */

#ifdef HAS_QPC

unsigned __int64 time_frequency = 0ui64;
typedef unsigned __int64 time_of_day_t;
#  define TICKS_PER_SEC time_frequency
#  define get_time_of_day(into) QueryPerformanceCounter((LARGE_INTEGER*)&into)
#  define get_ticks_between(typ, s, e, ticks, overflow) STMT_START { \
    overflow = 0; /* XXX whats this? */ \
    ticks = (e-s); \
} STMT_END

#elif defined(HAS_GETTIMEOFDAY)
/* on Win32 gettimeofday is always implimented in Perl, not the MS C lib, so
   either we use PerlProc_gettimeofday or win32_gettimeofday, depending on the
   Perl defines about NO_XSLOCKS and PERL_IMPLICIT_SYS, to simplify logic,
   we don't check the defines, just the macro symbol to see if it forwards to
   presumably the iperlsys.h vtable call or not */
#if defined(WIN32) && !defined(gettimeofday)
#  define gettimeofday win32_gettimeofday
#endif
typedef struct timeval time_of_day_t;
#  define TICKS_PER_SEC 1000000                 /* 1 million */
#  define get_time_of_day(into) gettimeofday(&into, NULL)
#  define get_ticks_between(typ, s, e, ticks, overflow) STMT_START { \
    overflow = 0; \
    ticks = ((e.tv_sec - s.tv_sec) * TICKS_PER_SEC + e.tv_usec - s.tv_usec); \
} STMT_END

#else

static int (*u2time)(pTHX_ UV *) = 0;
typedef UV time_of_day_t[2];
#  define TICKS_PER_SEC 1000000                 /* 1 million */
#  define get_time_of_day(into) (*u2time)(aTHX_ into)
#  define get_ticks_between(typ, s, e, ticks, overflow)  STMT_START { \
    overflow = 0; \
    ticks = ((e[0] - s[0]) * (typ)TICKS_PER_SEC + e[1] - s[1]); \
} STMT_END

#endif
#endif
#endif

/* CPAN #28912: MSWin32 and AIX as only platforms do not export PERL_CORE functions,
   such as Perl_debop
   so disable this feature. cygwin gcc-3 --export-all-symbols was non-strict, gcc-4 is.
   POSIX with export PERL_DL_NONLAZY=1 also fails. This is checked in Makefile.PL
   but cannot be solved for clients adding it.
*/
#if !defined (DISABLE_PERL_CORE_EXPORTED) &&                            \
  (defined(WIN32) ||                                                    \
   defined(_MSC_VER) || defined(__MINGW32_VERSION) ||			\
   (defined(__CYGWIN__) && (__GNUC__ > 3)) || defined(AIX))
# define DISABLE_PERL_CORE_EXPORTED
#endif

STATIC U32 opcount[MAXO];
STATIC time_of_day_t optimes[MAXO];

/* From B::C */
STATIC int
my_runops(pTHX)
{
  int ignore = 0;
#if 0
  /* ignore all ops from our subs */
  HV* ign_stash = get_hv( "B::Stats::", 0 );
  if (!CopSTASH_eq(PL_curcop, PL_debstash)) {
    OP *o = PL_op;
    HV *stash = NULL;
    /* from Perl_debop */
    switch (o->op_type) {
    case OP_CONST:
	/* With ITHREADS, consts are stored in the pad, and the right pad
	 * may not be active here, so check.
	 * Looks like only during compiling the pads are illegal.
	 */
#ifdef USE_ITHREADS
	if ((((SVOP*)o)->op_sv) || !IN_PERL_COMPILETIME)
#endif
	  stash = GvSTASH(cSVOPo_sv);
	break;
    case OP_GVSV:
    case OP_GV:
	if (cGVOPo_gv) {
	    stash = GvSTASH(cGVOPo_gv);
	}
	break;
    default:
	break;
    }
    ignore = stash == ign_stash;
  }
#endif

  DEBUG_v(Perl_deb(aTHX_ "Entering new RUNOPS level (B::Stats)\n"));
  do {
#if (PERL_VERSION < 13) || ((PERL_VERSION == 13) && (PERL_SUBVERSION < 2))
    PERL_ASYNC_CHECK();
#endif
    if (PL_debug) {
      if (PL_watchaddr && (*PL_watchaddr != PL_watchok))
	PerlIO_printf(Perl_debug_log,
		      "WARNING: %"UVxf" changed from %"UVxf" to %"UVxf"\n",
		      PTR2UV(PL_watchaddr), PTR2UV(PL_watchok),
		      PTR2UV(*PL_watchaddr));
#if !defined(DISABLE_PERL_CORE_EXPORTED) && defined(DEBUGGING)
# if (PERL_VERSION > 7)
      if (DEBUG_s_TEST_) debstack();
      if (DEBUG_t_TEST_) debop(PL_op);
# else
      DEBUG_s(debstack());
      DEBUG_t(debop(PL_op));
# endif
#endif
    }
  if (!ignore) {
    opcount[PL_op->op_type]++;
#ifdef DEBUGGING
    if (DEBUG_v_TEST_) {
# ifndef DISABLE_PERL_CORE_EXPORTED
      debop(PL_op);
# endif
      PerlIO_printf(Perl_debug_log, "Counted %d for %s\n",
		    opcount[PL_op->op_type]+1, PL_op_name[PL_op->op_type]);
    }
#endif
  }
  } while ((PL_op = CALL_FPTR(PL_op->op_ppaddr)(aTHX)));
  DEBUG_v(Perl_deb(aTHX_ "leaving RUNOPS level (B::Stats)\n"));

  TAINT_NOT;
  return 0;
}

void
reset_rcount() {
#if 1
  memset(opcount, 0, sizeof(opcount));
#else
  register int i;
  for (i=0; i < MAXO; i++) {
    opcount[i] = 0;
  }
#endif
}
/* returns an SV ref to AV with caller now owning the SV ref */
SV *
rcount_all(pTHX) {
  AV * av;
  int i;
  av = newAV();
  for (i=0; i < MAXO; i++) {
    av_store(av, i, newSViv(opcount[i]));
  }
  return newRV_noinc((SV*)av);
}

MODULE = B::Stats  PACKAGE = B::Stats

PROTOTYPES: DISABLE

U32
rcount(opcode)
	IV opcode
  CODE:
	RETVAL = opcount[opcode];
  OUTPUT:
	RETVAL

SV *
rcount_all()
  C_ARGS:
    aTHX

void
reset_rcount()

void
_xs_collect_env()
  CODE:
	/* walk stashes in C and store in %B_env before B is loaded,
	   to be able to detect if our testfunc loads B and its 14 deps itself.
	 */

void
END(...)
PREINIT:
    SV * sv;
PPCODE:
    PUSHMARK(SP);
    PUSHs(sv_2mortal(rcount_all(aTHX)));
    PUTBACK;
    call_pv("B::Stats::_end", G_VOID);
    return; /* skip implicity PUTBACK */

void
INIT(...)
PPCODE:
    PUTBACK;
    reset_rcount();
    return; /* skip implicity PUTBACK */

BOOT:
{
  reset_rcount();
  PL_runops = my_runops;
}
