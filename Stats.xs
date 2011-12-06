#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

STATIC AV* runtime; /* [count, ppaddr] */ 

STATIC OP *
call_pp (pTHX_) {
  AV* av;
  SV **elep  = av_fetch(runtime, PL_op->op_type, TRUE);
  assert(*elep);
  av = (AV*)SvRV(*elep);
  SV **count = av_fetch(av, 0, TRUE);
  SV **orig  = av_fetch(av, 1, TRUE);
  assert(orig);
  SvIV_set(*count, SvIVX(*count)+1);
  PL_op->op_ppaddr = SvIVX(*orig);
  return CALL_FPTR (INT2PTR(Perl_ppaddr_t,SvIVX(*orig))) (aTHX);
}

MODULE = B::Stats  PACKAGE = B::Stats

PROTOTYPES: DISABLE

BOOT:
  {
    int i;
    runtime = get_av("B::Stats::runtime", 0);
    av_extend(runtime, MAXO);
    for (i=0; i < MAXO; i++) {
      AV *av = newAV();
      av_store(av, 0, newSViv(0));
      av_store(av, 1, newSViv(PTR2IV(PL_ppaddr[i])));
      av_store(runtime, i, newRV((SV*)av));
      PL_ppaddr[i] = call_pp;
    }
  }
