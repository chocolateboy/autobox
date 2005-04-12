#include "ppport.h"

#if (PTRSIZE == 8)
#define PTR_TABLE_HASH(ptr) (PTR2UV(ptr) >> 3)
#else
#define PTR_TABLE_HASH(ptr) (PTR2UV(ptr) >> 2)
#endif

static PTR_TBL_t * ptr_table_new();
static void * ptr_table_fetch(PTR_TBL_t *tbl, void *sv);
static void ptr_table_store(PTR_TBL_t *tbl, void *oldv, void *newv);
static void ptr_table_grow(PTR_TBL_t *tbl);
static void ptr_table_clear(PTR_TBL_t *tbl);
static void ptr_table_free(PTR_TBL_t *tbl);

/* create a new pointer-mapping table */

static PTR_TBL_t *
ptr_table_new()
{
	PTR_TBL_t *tbl;
	Newz(0, tbl, 1, PTR_TBL_t);
	tbl->tbl_max = 511;
	tbl->tbl_items = 0;
	Newz(0, tbl->tbl_ary, tbl->tbl_max + 1, PTR_TBL_ENT_t*);
	return tbl;
}

/* map an existing pointer using a table */

static void *
ptr_table_fetch(PTR_TBL_t *tbl, void *sv)
{
	PTR_TBL_ENT_t *tblent;
	UV hash = PTR_TABLE_HASH(sv);
	tblent = tbl->tbl_ary[hash & tbl->tbl_max];

	for (; tblent; tblent = tblent->next) {
		if (tblent->oldval == sv) {
			/* Perl_warn(aTHX_ "    found value in ptr_table: 0x%x => 0x%x\n", sv, tblent->newval); */
			return tblent->newval;
		}
	}
	return (void*)NULL;
}

/* add a new entry to a pointer-mapping table */

static void
ptr_table_store(PTR_TBL_t *tbl, void *oldv, void *newv)
{
	PTR_TBL_ENT_t *tblent, **otblent;
	/* XXX this may be pessimal on platforms where pointers aren't good
	 * hash values e.g. if they grow faster in the most significant
	 * bits */
	UV hash = PTR_TABLE_HASH(oldv);
	bool empty = 1;
	/* Perl_warn(aTHX_ "    storing value in ptr_table: 0x%x => 0x%x\n", oldv, newv); */

	otblent = &tbl->tbl_ary[hash & tbl->tbl_max];
	for (tblent = *otblent; tblent; empty=0, tblent = tblent->next) {
		if (tblent->oldval == oldv) {
			tblent->newval = newv;
			return;
		}
	}
	Newz(0, tblent, 1, PTR_TBL_ENT_t);
	tblent->oldval = oldv;
	tblent->newval = newv;
	tblent->next = *otblent;
	*otblent = tblent;
	tbl->tbl_items++;
	if (!empty && tbl->tbl_items > tbl->tbl_max)
		ptr_table_grow(tbl);
}

/* double the hash bucket size of an existing ptr table */

static void
ptr_table_grow(PTR_TBL_t *tbl)
{
	PTR_TBL_ENT_t **ary = tbl->tbl_ary;
	UV oldsize = tbl->tbl_max + 1;
	UV newsize = oldsize * 2;
	UV i;

	Renew(ary, newsize, PTR_TBL_ENT_t*);
	Zero(&ary[oldsize], newsize-oldsize, PTR_TBL_ENT_t*);
	tbl->tbl_max = --newsize;
	tbl->tbl_ary = ary;
	for (i=0; i < oldsize; i++, ary++) {
		PTR_TBL_ENT_t **curentp, **entp, *ent;
		if (!*ary)
			continue;
		curentp = ary + oldsize;
		for (entp = ary, ent = *ary; ent; ent = *entp) {
			if ((newsize & PTR_TABLE_HASH(ent->oldval)) != i) {
				*entp = ent->next;
				ent->next = *curentp;
				*curentp = ent;
				continue;
			}
			else
				entp = &ent->next;
		}
	}
}

/* remove all the entries from a ptr table */

static void
ptr_table_clear(PTR_TBL_t *tbl)
{
	register PTR_TBL_ENT_t **array;
	register PTR_TBL_ENT_t *entry;
	register PTR_TBL_ENT_t *oentry = Null(PTR_TBL_ENT_t*);
	UV riter = 0;
	UV max;

	if (!tbl || !tbl->tbl_items) {
		return;
	}

	array = tbl->tbl_ary;
	entry = array[0];
	max = tbl->tbl_max;

	for (;;) {
		if (entry) {
			oentry = entry;
			entry = entry->next;
			Safefree(oentry);
		}
		if (!entry) {
			if (++riter > max) {
				break;
			}
			entry = array[riter];
		}
	}

	tbl->tbl_items = 0;
}

/* clear and free a ptr table */

static void
ptr_table_free(PTR_TBL_t *tbl)
{
	/* Perl_warn(aTHX_ "freeing ptr table\n"); */
	if (!tbl) {
		return;
	}
	ptr_table_clear(tbl);
	Safefree(tbl->tbl_ary);
	Safefree(tbl);
}
