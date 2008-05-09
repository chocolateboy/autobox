#define PERL_CORE

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#define NEED_sv_2pv_flags
#include "ppport.h"

#include "ptable.h"

static PTABLE_t *AUTOBOX_OP_MAP = NULL;
static U32 AUTOBOX_SCOPE_DEPTH = 0;
static OP *(*autobox_old_ck_subr)(pTHX_ OP *op) = NULL;

OP * autobox_ck_subr(pTHX_ OP *o);
OP * autobox_method_named(pTHX);
OP * autobox_method(pTHX);
static SV * autobox_method_common(pTHX_ SV * meth, U32* hashp); 

OP * autobox_ck_subr(pTHX_ OP *o) {
    /*
     * work around a %^H scoping bug by checking that PL_hints (which is properly scoped) & an unused
     * PL_hints bit (0x100000) is true
     */
    if ((PL_hints & 0x120000) == 0x120000) {
        OP *prev = ((cUNOPo->op_first->op_sibling) ? cUNOPo : ((UNOP*)cUNOPo->op_first))->op_first;
        OP *o2 = prev->op_sibling;
        OP *cvop;

        for (cvop = o2; cvop->op_sibling; cvop = cvop->op_sibling);

        /* don't autobox if the receiver is a bareword */
        if ((cvop->op_type == OP_METHOD) || ((cvop->op_type == OP_METHOD_NAMED) && !(o2->op_private & OPpCONST_BARE))) {
            const char * meth = SvPVX_const(((SVOP *)cvop)->op_sv);

            /*
             * the bareword flag is not set on the receivers of the import, unimport
             * and VERSION messages faked up by use() and no(), so exempt them
             */
            if ((cvop->op_type == OP_METHOD) ||
		(strNE(meth, "import") && strNE(meth, "unimport") && strNE(meth, "VERSION"))) {
                HV *table = GvHV(PL_hintgv);
                SV **svp;

                if (table && (svp = hv_fetch(table, "autobox", 7, FALSE)) && *svp && SvOK(*svp)) {
                    cvop->op_flags |= OPf_SPECIAL;
                    cvop->op_ppaddr = cvop->op_type == OP_METHOD ? autobox_method : autobox_method_named;
                    PTABLE_store(AUTOBOX_OP_MAP, cvop, SvRV(*svp));
                }
            }
        }
    }

    return autobox_old_ck_subr(aTHX_ o);
}

OP* autobox_method(pTHX) {
    dVAR; dSP;
    SV * const sv = TOPs;
    SV * cv;
    
    if (SvROK(sv)) {
        cv = SvRV(sv);
        if (SvTYPE(cv) == SVt_PVCV) {
            SETs(cv);
            RETURN;
        }
    }

    cv = autobox_method_common(aTHX_ sv, NULL);

    if (cv) {
        SETs(cv);
        RETURN;
    } else {
        return PL_ppaddr[OP_METHOD](aTHXR);
    }
}

OP* autobox_method_named(pTHX) {
    dVAR; dSP;
    SV * const sv = cSVOP_sv;
    U32 hash = SvSHARED_HASH(sv);
    SV * cv;

    cv = autobox_method_common(aTHX_ sv, &hash);

    if (cv) {
        XPUSHs(cv);
        RETURN;
    } else {
        return PL_ppaddr[OP_METHOD_NAMED](aTHXR);
    }
}

/* returns either the method, or NULL, meaning delegate to the original op */
static SV * autobox_method_common(pTHX_ SV * meth, U32* hashp) {
    SV * const sv = *(PL_stack_base + TOPMARK + 1);

    /* if autobox is enabled (in scope) for this op and the receiver isn't an object... */
    if ((PL_op->op_flags & OPf_SPECIAL) && !(SvOBJECT(SvROK(sv) ? SvRV(sv) : sv))) {
        HV * autobox_bindings;

        if (SvGMAGICAL(sv))
            mg_get(sv);

        /* this is the "bindings hash" that maps datatypes to package names */
        autobox_bindings = (HV *)(PTABLE_fetch(AUTOBOX_OP_MAP, PL_op));

        if (autobox_bindings) {
            const char * reftype; /* autobox_bindings key */
            SV **svp; /* pointer to autobox_bindings value */

            /*
             * the type is either the receiver's reftype() ("SCALAR" if it's not a ref), or UNDEF if
             * it's not defined
             */
            reftype = SvOK(sv) ? sv_reftype((SvROK(sv) ? SvRV(sv) : sv), 0) : "UNDEF";
            svp = hv_fetch(autobox_bindings, reftype, strlen(reftype), 0);

            if (svp && SvOK(*svp)) {
                SV * packsv = *svp;
                STRLEN packlen;
                HV * stash;
                GV * gv;
                const char * packname = SvPV_const(packsv, packlen);

                /* NOTE: stash may be null, hope hv_fetch_ent and gv_fetchmethod can cope (it seems they can) */
                stash = gv_stashpvn(packname, packlen, FALSE);

                if (hashp) {
                    const HE* const he = hv_fetch_ent(stash, meth, 0, *hashp);  /* shortcut for simple names */

                    if (he) {
                        gv = (GV*)HeVAL(he);
                        if (isGV(gv) && GvCV(gv) && (!GvCVGEN(gv) || GvCVGEN(gv) == PL_sub_generation)) {
                            return ((SV*)GvCV(gv));
                        }
                    }
                }

                /* SvPVX_const(meth): the method name as a const char * */
                gv = gv_fetchmethod(stash ? stash : (HV*)packsv, SvPVX_const(meth));

                if (gv) {
                    return(isGV(gv) ? (SV*)GvCV(gv) : (SV*)gv);
                }
            }
        }
    }

    return NULL;
}

MODULE = autobox                PACKAGE = Autobox

PROTOTYPES: ENABLE

BOOT:
AUTOBOX_OP_MAP = PTABLE_new(); if (!AUTOBOX_OP_MAP) Perl_croak(aTHX_ "Can't initialize op map");

void
enterscope()
    PROTOTYPE:
    CODE: 
        if (AUTOBOX_SCOPE_DEPTH > 0) {
            ++AUTOBOX_SCOPE_DEPTH;
        } else {
            AUTOBOX_SCOPE_DEPTH = 1;
            /*
             * capture the check routine in scope when autobox is used.
             * usually, this will be Perl_ck_subr, though, in principle,
             * it could be a bespoke checker spliced in by another module.
             */
            autobox_old_ck_subr = PL_check[OP_ENTERSUB];
            PL_check[OP_ENTERSUB] = autobox_ck_subr;
        }

void
leavescope()
    PROTOTYPE:
    CODE: 
        if (AUTOBOX_SCOPE_DEPTH > 1) {
            --AUTOBOX_SCOPE_DEPTH;
        } else {
            AUTOBOX_SCOPE_DEPTH = 0;
            PL_check[OP_ENTERSUB] = autobox_old_ck_subr;
        }

void
END()
    PROTOTYPE:
    CODE: 
        if (autobox_old_ck_subr) { /* make sure we got as far as initializing it */
            PL_check[OP_ENTERSUB] = autobox_old_ck_subr;
        }

        PTABLE_free(AUTOBOX_OP_MAP);
        AUTOBOX_OP_MAP = NULL;
        AUTOBOX_SCOPE_DEPTH = 0;

void
scope()
    PROTOTYPE:
    CODE: 
        XSRETURN_IV(PTR2IV(GvHV(PL_hintgv)));
