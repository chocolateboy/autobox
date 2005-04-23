#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

#include "ptable.h"

static PTABLE_t *AUTOBOX_OP_MAP = NULL;
static U32 AUTOBOX_SCOPE_DEPTH = 0;

OP * autobox_ck_method_named(pTHX_ OP *o);
OP * autobox_ck_subr(pTHX_ OP *o);
OP * autobox_method_named(pTHX);

/* the original is a no-op, so simply return o rather than delegating */
OP * autobox_ck_method_named(pTHX_ OP *o) {
	char *meth  = SvPVX(((SVOP *)o)->op_sv);
	/*
	 * workaround %^H scoping bug by checking that PL_hints (which is properly scoped) & 0x100000 is true
	 *
	 * the bareword flag is not set on the receivers of the import, unimport
	 * and VERSION messages faked up by use and no, so exempt them
	 */
	/* Perl_warn(aTHX_ "Perl_hints: 0x%x", PL_hints); */
	if (((PL_hints & 0x120000) == 0x120000) && strNE(meth, "import") && strNE(meth, "unimport") && strNE(meth, "VERSION")) {
		 HV *table = GvHV(PL_hintgv);
		 SV **svp;

		 if (table && (svp = hv_fetch(table, "autobox", 7, FALSE)) && *svp && SvOK(*svp)) {
			 PTABLE_store(AUTOBOX_OP_MAP, o, INT2PTR(void *, SvIVX(*svp)));
			 /* autoboxing has been disabled (by prematurely setting OPf_SPECIAL) because the receiver is a bareword */
			if (o->op_flags & OPf_SPECIAL) {
				 o->op_flags &= ~OPf_SPECIAL;
			} else {
				 o->op_flags |= OPf_SPECIAL;
				 o->op_ppaddr = MEMBER_TO_FPTR(autobox_method_named);
			}
		 }
	}
	return o;
}

/* handle barewords before delegating to the original check handler */
OP * autobox_ck_subr(pTHX_ OP *o) {
    OP *prev = ((cUNOPo->op_first->op_sibling) ? cUNOPo : ((UNOP*)cUNOPo->op_first))->op_first;
    OP *o2 = prev->op_sibling;
    OP *cvop;

    for (cvop = o2; cvop->op_sibling; cvop = cvop->op_sibling);

    if ((cvop->op_type == OP_METHOD_NAMED) && (o2->op_private & OPpCONST_BARE)) {
		cvop->op_flags |= OPf_SPECIAL;
	}

	return Perl_ck_subr(aTHX_ o);
}

OP* autobox_method_named(pTHX) {
    dSP;
    SV * meth = cSVOP_sv;
    U32 hash = SvUVX(meth);
	SV * sv;
    GV * gv = NULL;
    HV * stash;
    char * name;
    STRLEN namelen;
    char * packname = 0;
    SV  * packsv = Nullsv;
    STRLEN packlen;
	HE *he;

    name = SvPV(meth, namelen);
    sv = *(PL_stack_base + TOPMARK + 1);

    if (SvGMAGICAL(sv))
		mg_get(sv);

    if ((PL_op->op_flags & OPf_SPECIAL) && !(SvOBJECT(SvROK(sv) ? SvRV(sv) : sv))) {
        HV * autobox_handlers = (HV *)(PTABLE_fetch(AUTOBOX_OP_MAP, PL_op)); /* maps datatypes to package names */

        if (autobox_handlers) {
            char *reftype; /* autobox_handlers key */
            SV **svp; /* pointer to autobox_handlers value */

			reftype = SvOK(sv) ? sv_reftype((SvROK(sv) ? SvRV(sv) : sv), 0) : "UNDEF";
			svp = hv_fetch(autobox_handlers, reftype, strlen(reftype), 0);

            if (svp && SvOK(*svp)) {
				packsv = *svp;
				packname = SvPVX(packsv); /* fake the package name */
				packlen = strlen(packname);
				stash = gv_stashpvn(packname, packlen, FALSE);

#ifdef PL_stashcache /* not defined in 5.6.1 */
				if (stash) {
					SV * ref = newSViv(PTR2IV(stash));
					hv_store(PL_stashcache, packname, packlen, ref, 0); /* cache the stash */
				}
#endif

				/* NOTE: stash may be null, hope hv_fetch_ent and gv_fetchmethod can cope (it seems they can) */
				he = hv_fetch_ent(stash, meth, 0, hash); /* shortcut for simple names */

				if (he) {
					gv = (GV*)HeVAL(he);
					if (isGV(gv) && GvCV(gv) && (!GvCVGEN(gv) || GvCVGEN(gv) == PL_sub_generation)) {
						XPUSHs((SV*)GvCV(gv));
						RETURN;
					}
				}

				gv = gv_fetchmethod(stash ? stash : (HV*)packsv, name);
            }
        }
    }

	if (gv) {
		XPUSHs(isGV(gv) ? (SV*)GvCV(gv) : (SV*)gv);
		RETURN;
	} else {
		return Perl_pp_method_named(aTHX);
	}
}

MODULE = autobox		PACKAGE = Autobox

PROTOTYPES: ENABLE

BOOT:
AUTOBOX_OP_MAP = PTABLE_new(); if (!AUTOBOX_OP_MAP) croak ("Can't initialize op map");

void
enterscope()
	PROTOTYPE:
	CODE: 
		if (AUTOBOX_SCOPE_DEPTH > 0) {
			++AUTOBOX_SCOPE_DEPTH;
		} else {
			AUTOBOX_SCOPE_DEPTH = 1;
			/* Perl_warn("inside autobox::enterscope\n"); */
			PL_check[OP_METHOD_NAMED] = MEMBER_TO_FPTR(autobox_ck_method_named);
			PL_check[OP_ENTERSUB] = MEMBER_TO_FPTR(autobox_ck_subr);
		}

void
leavescope()
	PROTOTYPE:
	CODE: 
		if (AUTOBOX_SCOPE_DEPTH > 1) {
			--AUTOBOX_SCOPE_DEPTH;
		} else {
			AUTOBOX_SCOPE_DEPTH = 0;
			/* Perl_warn("inside autobox::leavescope\n"); */
			PL_check[OP_METHOD_NAMED] = MEMBER_TO_FPTR(Perl_ck_null);
			PL_check[OP_ENTERSUB] = MEMBER_TO_FPTR(Perl_ck_subr);
		}

void
cleanup()
	PROTOTYPE:
	CODE: 
		/* Perl_warn("inside autobox::cleanup\n"); */
		PL_check[OP_METHOD_NAMED] = MEMBER_TO_FPTR(Perl_ck_null);
		PL_check[OP_ENTERSUB] = MEMBER_TO_FPTR(Perl_ck_subr);
		PTABLE_free(AUTOBOX_OP_MAP);
		AUTOBOX_OP_MAP = NULL;
		AUTOBOX_SCOPE_DEPTH = 0;
