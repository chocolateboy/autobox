#define PERL_CORE

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#define NEED_sv_2pv_flags
#include "ppport.h"

#include "ptable.h"
/* #include <assert.h> */

static PTABLE_t *AUTOBOX_OP_MAP = NULL;
static U32 AUTOBOX_SCOPE_DEPTH = 0;
static OP *(*autobox_old_ck_subr)(pTHX_ OP *op) = NULL;
static U32 AUTOBOX_OLD_HINTS; /* snapshot of the original hints flags */

OP * autobox_ck_subr(pTHX_ OP *o);
OP * autobox_method_named(pTHX);

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
        if ((cvop->op_type == OP_METHOD_NAMED) && !(o2->op_private & OPpCONST_BARE)) {
            const char * meth = SvPVX_const(((SVOP *)cvop)->op_sv);

            /*
             * the bareword flag is not set on the receivers of the import, unimport
             * and VERSION messages faked up by use() and no(), so exempt them
             */
            if (strNE(meth, "import") && strNE(meth, "unimport") && strNE(meth, "VERSION")) {
                HV *table = GvHV(PL_hintgv);
                SV **svp;

                if (table && (svp = hv_fetch(table, "autobox", 7, FALSE)) && *svp && SvOK(*svp)) {
                    cvop->op_flags |= OPf_SPECIAL;
                    cvop->op_ppaddr = autobox_method_named;
                    PTABLE_store(AUTOBOX_OP_MAP, cvop, SvRV(*svp));
                }
            }
        }
    }

    /* assert(autobox_old_ck_subr != autobox_ck_subr); */
    return autobox_old_ck_subr(aTHX_ o);
}

OP* autobox_method_named(pTHX) {
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
             * the type is either the receiver's reftype(), "SCALAR" if it's not a ref, or UNDEF if
             * it's not defined
             */
            reftype = SvOK(sv) ? sv_reftype((SvROK(sv) ? SvRV(sv) : sv), 0) : "UNDEF";
            svp = hv_fetch(autobox_bindings, reftype, strlen(reftype), 0);

            if (svp && SvOK(*svp)) {
                SV * packsv = *svp;
                STRLEN packlen;
                const HE * he;
                HV * stash;
                GV * gv;
                const char * packname = SvPV_const(packsv, packlen);
                SV * meth = cSVOP_sv;

                /* NOTE: stash may be null, hope hv_fetch_ent and gv_fetchmethod can cope (it seems they can) */
                stash = gv_stashpvn(packname, packlen, FALSE);

                /* SvSHARED_HASH(meth): the hash code of the method name */
                he = hv_fetch_ent(stash, meth, 0, SvSHARED_HASH(meth)); /* shortcut for simple names */

                if (he) {
                    gv = (GV*)HeVAL(he);
                    if (isGV(gv) && GvCV(gv) && (!GvCVGEN(gv) || GvCVGEN(gv) == PL_sub_generation)) {
                        dSP;
                        XPUSHs((SV*)GvCV(gv));
                        RETURN;
                    }
                }

                /* SvPVX_const(meth): the method name as a const char * */
                gv = gv_fetchmethod(stash ? stash : (HV*)packsv, SvPVX_const(meth));

                if (gv) {
                    dSP;
                    XPUSHs(isGV(gv) ? (SV*)GvCV(gv) : (SV*)gv);
                    RETURN;
                }
            }
        }
    }

    return PL_ppaddr[OP_METHOD_NAMED](aTHX);
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
            AUTOBOX_OLD_HINTS = PL_hints;
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
            PL_hints = AUTOBOX_OLD_HINTS; /* restore the original hints */
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
