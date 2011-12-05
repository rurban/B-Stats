#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

typedef OP *(*hook_op_ppaddr_cb_t) (pTHX_ OP *, void *user_data);
typedef struct userdata_St {
  Perl_ppaddr_t orig;
  AV *count;
} userdata_t;

STATIC AV* runtime; /* [count, ppaddr] */ 

STATIC OP *
call_pp (pTHX_) {
  SV **elem  = av_fetch(runtime, PL_op->op_type, TRUE);
  SV **count = av_fetch(SvRV(*elem), 0, TRUE);
  SV **orig  = av_fetch(SvRV(*elem), 1, TRUE);
  SvIV_set(*count, SvIVX(*count)+1);
  return CALL_FPTR ((Perl_ppaddr_t)*orig) (aTHX);
}

MODULE = B::Stats  PACKAGE = B::Stats

PROTOTYPES: DISABLE

BOOT:
  {
    int i;
    runtime = get_av('B::Stats::runtime', 0);
    av_extend(runtime, MAXO);
    for (i=0; i < MAXO; i++) {
      AV *rv = newAV();
      av_store(rv, 0, newSViv(0));
      av_store(rv, 1, PL_ppaddr[i]);
      av_store(runtime, i, newSVrv(rv, NULL));
      PL_ppaddr[i] = call_pp;
    }
  }
