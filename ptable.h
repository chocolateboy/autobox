#include "ppport.h"

#if (PTRSIZE == 8)
#define PTABLE_HASH(ptr) (PTR2UV(ptr) >> 3)
#else
#define PTABLE_HASH(ptr) (PTR2UV(ptr) >> 2)
#endif

struct PTABLE_entry {
    struct	PTABLE_entry *	next;
    void *					key;
    void *					value;
};

struct PTABLE {
    struct PTABLE_entry ** 	tbl_ary;
    UV						tbl_max;
    UV						tbl_items;
};

typedef struct PTABLE_entry	PTABLE_ENTRY_t;
typedef struct PTABLE 		PTABLE_t;

static PTABLE_t * PTABLE_new();
static void * PTABLE_fetch(PTABLE_t *tbl, void *key);
static void PTABLE_store(PTABLE_t *tbl, void *key, void *value);
static void PTABLE_grow(PTABLE_t *tbl);
static void PTABLE_clear(PTABLE_t *tbl);
static void PTABLE_free(PTABLE_t *tbl);

/* create a new pointer => pointer table */

static PTABLE_t *
PTABLE_new()
{
	PTABLE_t *tbl;
	Newz(0, tbl, 1, PTABLE_t);
	tbl->tbl_max = 511;
	tbl->tbl_items = 0;
	Newz(0, tbl->tbl_ary, tbl->tbl_max + 1, PTABLE_ENTRY_t*);
	return tbl;
}

/* map an existing pointer using a table */

static void *
PTABLE_fetch(PTABLE_t *tbl, void *key)
{
	PTABLE_ENTRY_t *tblent;
	UV hash = PTABLE_HASH(key);
	tblent = tbl->tbl_ary[hash & tbl->tbl_max];

	for (; tblent; tblent = tblent->next) {
		if (tblent->key == key) {
			/* Perl_warn(aTHX_ "    found value in PTABLE: 0x%x => 0x%x\n", key, tblent->value); */
			return tblent->value;
		}
	}
	return (void*)NULL;
}

/* add a new entry to a pointer-mapping table */

static void
PTABLE_store(PTABLE_t *tbl, void *key, void *value)
{
	PTABLE_ENTRY_t *tblent, **otblent;
	/* XXX this may be pessimal on platforms where pointers aren't good
	 * hash values e.g. if they grow faster in the most significant
	 * bits */
	UV hash = PTABLE_HASH(key);
	bool empty = 1;
	/* Perl_warn(aTHX_ "    storing value in PTABLE: 0x%x => 0x%x\n", key, value); */

	otblent = &tbl->tbl_ary[hash & tbl->tbl_max];
	for (tblent = *otblent; tblent; empty=0, tblent = tblent->next) {
		if (tblent->key == key) {
			tblent->value = value;
			return;
		}
	}
	Newz(0, tblent, 1, PTABLE_ENTRY_t);
	tblent->key = key;
	tblent->value = value;
	tblent->next = *otblent;
	*otblent = tblent;
	tbl->tbl_items++;
	if (!empty && tbl->tbl_items > tbl->tbl_max)
		PTABLE_grow(tbl);
}

/* double the hash bucket size of an existing ptr table */

static void
PTABLE_grow(PTABLE_t *tbl)
{
	PTABLE_ENTRY_t **ary = tbl->tbl_ary;
	UV oldsize = tbl->tbl_max + 1;
	UV newsize = oldsize * 2;
	UV i;

	Renew(ary, newsize, PTABLE_ENTRY_t*);
	Zero(&ary[oldsize], newsize-oldsize, PTABLE_ENTRY_t*);
	tbl->tbl_max = --newsize;
	tbl->tbl_ary = ary;
	for (i=0; i < oldsize; i++, ary++) {
		PTABLE_ENTRY_t **curentp, **entp, *ent;
		if (!*ary)
			continue;
		curentp = ary + oldsize;
		for (entp = ary, ent = *ary; ent; ent = *entp) {
			if ((newsize & PTABLE_HASH(ent->key)) != i) {
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
PTABLE_clear(PTABLE_t *tbl)
{
	register PTABLE_ENTRY_t **array;
	register PTABLE_ENTRY_t *entry;
	register PTABLE_ENTRY_t *oentry = Null(PTABLE_ENTRY_t*);
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
PTABLE_free(PTABLE_t *tbl)
{
	/* Perl_warn(aTHX_ "freeing ptr table\n"); */
	if (!tbl) {
		return;
	}
	PTABLE_clear(tbl);
	Safefree(tbl->tbl_ary);
	Safefree(tbl);
}
