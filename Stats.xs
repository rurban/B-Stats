#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

STATIC U32 opcount[MAXO];

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
  if (!ignore) {
    opcount[PL_op->op_type]++;
    if (DEBUG_v_TEST_) {
      debop(PL_op);
      PerlIO_printf(Perl_debug_log, "Counted %d for %s\n", 
		    opcount[PL_op->op_type]+1, PL_op_name[PL_op->op_type]);
    }
  }

  DEBUG_l(Perl_deb(aTHX_ "Entering new RUNOPS level (B::Stats)\n"));
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
#if defined(DEBUGGING) \
   && !(defined(_WIN32) || (defined(__CYGWIN__) && (__GNUC__ > 3)) || defined(AIX))
# if (PERL_VERSION > 7)
      if (DEBUG_s_TEST_) debstack();
      if (DEBUG_t_TEST_) debop(PL_op);
# else
      DEBUG_s(debstack());
      DEBUG_t(debop(PL_op));
# endif
#endif
    }
  } while ((PL_op = CALL_FPTR(PL_op->op_ppaddr)(aTHX)));
  DEBUG_l(Perl_deb(aTHX_ "leaving RUNOPS level (B::Stats)\n"));

  TAINT_NOT;
  return 0;
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

BOOT:
#if 1
	memset(opcount, 0, sizeof(opcount[MAXO]));
#else
	register int i;
	for (i=0; i < MAXO; i++) {
	  opcount[i] = 0;
	}
#endif
	PL_runops = my_runops;
