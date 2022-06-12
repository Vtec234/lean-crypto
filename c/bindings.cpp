
#define CRYPTO_NAMESPACE(x) x
#include <lean/lean.h>
#include <stdlib.h>
#include <string.h>
extern "C" {
#include "crypto_kem.h"
#include "operations.h"

#include "controlbits.h"
#include "randombytes.h"
#include "crypto_hash.h"
#include "encrypt.h"
#include "decrypt.h"
#include "params.h"
#include "sk_gen.h"
#include "uint64_sort.h"
#include "util.h"

#include <openssl/conf.h>
#include <openssl/evp.h>
#include <openssl/err.h>

}
#include <gmp.h>

namespace lean {
    lean_obj_res io_wrap_handle(FILE * hfile);
}

/**
 * @brief Open a stream using a file descriptor.
 *
 * @param fd
 * @return Handle
 */
extern "C" LEAN_EXPORT lean_obj_res open_fd_write(uint32_t fd) {
    FILE* fp = fdopen(fd, "w");
    if (!fp) {
        return lean_io_result_mk_error(lean_mk_io_user_error(lean_mk_string("FILE_OPEN_ERROR Lean")));
    }
    return lean_io_result_mk_ok(lean::io_wrap_handle(fp));
}

static void init_gf_array(gf* s, b_lean_obj_arg obj) {
    for (size_t i = 0; i != lean_array_size(obj); ++i) {
        s[i] = lean_unbox_uint32(lean_array_get_core(obj, i));
    }
}

extern "C" uint8_t lean_byte_array_decide_eq(b_lean_obj_arg x, b_lean_obj_arg y) {
    size_t n = lean_sarray_size(x);
    if (n != lean_sarray_size(y)) {
        return 0;
    }
    if (memcmp(lean_sarray_cptr(x), lean_sarray_cptr(y), n)) {
        return 0;
    }
    return 1;
}

static inline
lean_obj_res lean_alloc_sarray1(unsigned elem_size, size_t size) {
    return lean_alloc_sarray(elem_size, size, size);
}

static
void handleErrors(void)
{
    ERR_print_errors_fp(stderr);
    abort();
}

extern "C" LEAN_EXPORT lean_object * lean_alloc_mpz(mpz_t v);
extern "C" LEAN_EXPORT void lean_extract_mpz_value(lean_object * o, mpz_t v);

static lean_obj_res nat_import_from_bytes(size_t n, const unsigned char* a) {
    if (n == 0)
        return lean_box(0);
    mpz_t r;
    mpz_init2(r, 8*n);
    mpz_import(r, n, 1, 1, -1, 0, a);

    if (mpz_cmp_ui(r, LEAN_MAX_SMALL_NAT) <= 0) {
        lean_obj_res o = lean_box(mpz_get_ui(r));
        mpz_clear(r);
        return o;
    }
    return lean_alloc_mpz(r);
}

static void nat_export_to_bytes(size_t n, unsigned char* a, b_lean_obj_arg x) {
    if (n == 0)
        return;
    mpz_t xz;
    if (lean_is_scalar(x)) {
        mpz_init_set_ui(xz, lean_unbox(x));
    } else {
        mpz_init(xz);
        lean_extract_mpz_value(x, xz);
    }

    size_t count;
    mpz_export(a, &count, 1, 1, -1, 0, xz);
    assert(count <= n);
    if (count < n) {
        memmove(a + (n-count), a, count);
        memset(a, 0, n-count);
    }
    // Set remaining bits
    mpz_clear(xz);
}

/*
   Use whatever AES implementation you have. This uses AES from openSSL library
      key - 256-bit AES key
      ctr - a 128-bit plaintext value
      buffer - a 128-bit ciphertext value
*/
static void
AES256_ECB(unsigned char *key, unsigned char *ctr, unsigned char *buffer)
{
    EVP_CIPHER_CTX *ctx;

    int len;

    /* Create and initialise the context */
    if(!(ctx = EVP_CIPHER_CTX_new())) handleErrors();

    if(1 != EVP_EncryptInit_ex(ctx, EVP_aes_256_ecb(), NULL, key, NULL))
        handleErrors();

    if(1 != EVP_EncryptUpdate(ctx, buffer, &len, ctr, 16))
        handleErrors();

    /* Clean up */
    EVP_CIPHER_CTX_free(ctx);
}

inline static lean_obj_res lean_mk_pair(lean_obj_arg x, lean_obj_arg y) {
    lean_object * r = lean_alloc_ctor(0, 2, 0);
    lean_ctor_set(r, 0, x);
    lean_ctor_set(r, 1, y);
    return r;
}

static void
my_AES256_CTR_DRBG_Update(unsigned char *provided_data,
                       unsigned char *Key,
                       unsigned char *V)
{
    unsigned char   temp[48];
    int i;
    int j;

    for (i=0; i<3; i++) {
        /* increment V */
        for (j=15; j>=0; j--) {
            if ( V[j] == 0xff )
                V[j] = 0x00;
            else {
                V[j]++;
                break;
            }
        }

        AES256_ECB(Key, V, temp+16*i);
    }
    if ( provided_data != NULL )
        for (i=0; i<48; i++)
            temp[i] ^= provided_data[i];
    memcpy(Key, temp, 32);
    memcpy(V, temp+32, 16);
}

extern "C" lean_obj_res lean_random_init(b_lean_obj_arg entropy_input_array) {
    assert(lean_sarray_size(entropy_input_array) == 48);
    unsigned char* entropy_input = lean_sarray_cptr(entropy_input_array);

    lean_obj_res key_array = lean_alloc_sarray1(1, 32);
    uint8_t* key = lean_sarray_cptr(key_array);

    lean_obj_res v_array = lean_alloc_sarray1(1, 16);
    uint8_t* v = lean_sarray_cptr(v_array);

    unsigned char   seed_material[48];
    memcpy(seed_material, entropy_input, 48);
    memset(key, 0x00, 32);
    memset(v, 0x00, 16);
    my_AES256_CTR_DRBG_Update(seed_material, key, v);
    return lean_mk_pair(key_array, v_array);
}

extern "C" lean_obj_res lean_random_bytes(b_lean_obj_arg drbg_obj, b_lean_obj_arg size) {
    if (LEAN_UNLIKELY(!lean_is_scalar(size))) {
        lean_internal_panic_out_of_memory();
    }
    size_t xlen = lean_unbox(size);

    uint8_t* key_input = lean_sarray_cptr(lean_ctor_get(drbg_obj, 0));
    lean_obj_res key_array = lean_alloc_sarray1(1, 32);
    uint8_t* key = lean_sarray_cptr(key_array);
    memcpy(key, key_input, 32);

    uint8_t* v_input   = lean_sarray_cptr(lean_ctor_get(drbg_obj, 1));
    lean_obj_res v_array = lean_alloc_sarray1(1, 16);
    uint8_t* v = lean_sarray_cptr(v_array);
    memcpy(v, v_input, 16);

    lean_obj_res r = lean_alloc_sarray1(1, xlen);
    uint8_t* x = lean_sarray_cptr(r);

    unsigned char   block[16];
    int             i = 0;
    int j;

    while ( xlen > 0 ) {
        /* increment V */
        for (j=15; j>=0; j--) {
            if ( v[j] == 0xff )
                v[j] = 0x00;
            else {
                v[j]++;
                break;
            }
        }
        AES256_ECB(key, v, block);
        if ( xlen > 15 ) {
            memcpy(x+i, block, 16);
            i += 16;
            xlen -= 16;
        }
        else {
            memcpy(x+i, block, xlen);
            xlen = 0;
        }
    }
    my_AES256_CTR_DRBG_Update(NULL, key, v);

    return lean_mk_pair(r, lean_mk_pair(key_array, v_array));
}

inline static lean_obj_res lean_mk_option_none(void) {
    return lean_alloc_ctor(0, 0, 0);
}

inline static lean_obj_res lean_mk_option_some(lean_obj_arg v) {
    lean_object * r = lean_alloc_ctor(1, 1, 0);
    lean_ctor_set(r, 0, v);
    return r;
}

extern "C" lean_obj_res lean_shake256(b_lean_obj_arg size_obj, b_lean_obj_arg in_obj) {
    if (LEAN_UNLIKELY(!lean_is_scalar(size_obj))) {
        lean_internal_panic_out_of_memory();
    }
    size_t size = lean_unbox(size_obj);
    lean_obj_res r_obj = lean_alloc_sarray1(1, size);

    shake(lean_sarray_cptr(r_obj), size, lean_sarray_cptr(in_obj), lean_sarray_size(in_obj));

    return r_obj;
}

extern "C" uint16_t lean_gf_add(uint16_t x, uint16_t y) {
    return gf_add(x, y);
}

extern "C" uint16_t lean_gf_mul(uint16_t x, uint16_t y) {
    return gf_mul(x, y);
}

extern "C" lean_obj_res lean_GF_mul(b_lean_obj_arg x_obj, b_lean_obj_arg y_obj) {
    gf x[lean_array_size(x_obj)];
    init_gf_array(x, x_obj);

    gf y[lean_array_size(y_obj)];
    init_gf_array(y, y_obj);

    gf r[SYS_T];
    GF_mul(r, x, y);

    lean_obj_res r_obj = lean_alloc_array(SYS_T, SYS_T);
    for (size_t i = 0; i != SYS_T; ++i) {
        lean_array_set_core(r_obj, i, lean_box_uint32(r[i]));
    }
    return r_obj;
}


static
void xor_array(gf* out, gf* x, gf* y, size_t n) {
    for (size_t c = 0; c < n; c++) {
        out[c] = x[c] ^ y[c];
    }
}

extern "C" uint16_t lean_gf_iszero(uint16_t x) {
    return gf_iszero(x);
}

extern "C"
uint16_t lean_gf_inv(uint16_t x) {
    gf inv = gf_inv(x);
    return inv;
}

extern "C" lean_obj_res lean_store_gf(b_lean_obj_arg irr_obj) {
    assert(lean_array_size(irr_obj) == SYS_T);
    gf irr[SYS_T];
    init_gf_array(irr, irr_obj);

    lean_obj_res sk_obj = lean_alloc_sarray1(1, 2 * SYS_T);
    uint8_t* sk = lean_sarray_cptr(sk_obj);

    // generating irreducible polynomial
    for (size_t i = 0; i < SYS_T; i++)
        store_gf(sk + i*2, irr[i]);

    return sk_obj;
}

extern "C" uint16_t lean_bitrev(uint16_t x) {
    return bitrev(x);
}

/* input: polynomial f and field element a */
/* return f(a) */
static
gf my_eval(const gf *f, gf a) {
	gf r = f[ SYS_T ];

	for (int i = SYS_T-1; i >= 0; i--) {
		r = gf_mul(r, a);
		r = gf_add(r, f[i]);
	}

	return r;
}

extern "C"  uint16_t lean_eval(b_lean_obj_arg g_obj, uint16_t x) {
	gf g[ SYS_T+1 ]; // Goppa polynomial
    for (size_t i = 0; i != SYS_T+1; ++i) {
        g[i] = lean_unbox_uint32(lean_array_get_core(g_obj, i));
    }
    return my_eval(g, x);
}

extern "C" lean_obj_res lean_controlbitsfrompermutation(b_lean_obj_arg pi_obj) {

    const size_t perm_count = 1 << GFBITS;
    assert(lean_array_size(pi_obj) == perm_count);
    int16_t pi[perm_count];
    for (size_t i = 0; i != perm_count; ++i) {
        pi[i] = lean_unbox_uint32(lean_array_get_core(pi_obj, i));
    }

    lean_obj_res sk_obj = lean_alloc_sarray1(1, COND_BYTES);
    uint8_t* sk = lean_sarray_cptr(sk_obj);

    controlbitsfrompermutation(sk, pi, GFBITS, 1 << GFBITS);

    return sk_obj;
}

extern "C" gf bitrev(gf a);
extern "C" void apply_benes(unsigned char * r, const unsigned char * bits, int rev);

#define min(a, b) ((a < b) ? a : b)

/* the Berlekamp-Massey algorithm */
/* input: s, sequence of field elements */
/* output: out, minimal polynomial of s */
static
void my_bm(gf *out, const gf *s)
{
	//

	gf B[SYS_T+1];
	for (int i = 0; i < SYS_T+1; i++)
		B[i] = 0;
	B[1] = 1;

	gf C[SYS_T+1];
	for (int i = 0; i < SYS_T+1; i++)
		C[i] = 0;
	C[0] = 1;


	uint16_t L = 0;
	gf b = 1;

	//
	for (uint16_t N = 0; N < 2 * SYS_T; N++) {
		gf d = 0;
		for (int i = 0; i <= min(N, SYS_T); i++)
			d ^= gf_mul(C[i], s[ N-i]);

		gf mne = ((d-1)>>15)-1;
        gf mle = N; mle -= 2*L; mle >>= 15; mle -= 1;
		mle &= mne;

    	gf T[ SYS_T+1  ];
		for (int i = 0; i <= SYS_T; i++)
			T[i] = C[i];

        gf f = gf_frac(b, d);

		for (int i = 0; i <= SYS_T; i++)
			C[i] ^= gf_mul(f, B[i]) & mne;

		L = (L & ~mle) | ((N+1-L) & mle);

		for (int i = 0; i <= SYS_T; i++)
			B[i] = (B[i] & ~mle) | (T[i] & mle);

		b = (b & ~mle) | (d & mle);

		for (int i = SYS_T; i >= 1; i--)
            B[i] = B[i-1];
		B[0] = 0;
	}

	for (int i = 0; i <= SYS_T; i++)
		out[i] = C[ SYS_T-i ];
}

extern "C" lean_obj_res lean_bm(b_lean_obj_arg s_obj, b_lean_obj_arg s2_obj) {
    assert(lean_array_size(s_obj) == 2*SYS_T);
	gf s[2*SYS_T];
    init_gf_array(s, s_obj);

	gf locator[ SYS_T+1 ];
	my_bm(locator, s);

    lean_obj_res locator_obj = lean_alloc_array(SYS_T+1, SYS_T+1);
    for (size_t i = 0; i != SYS_T+1; ++i) {
        lean_array_set_core(locator_obj, i, lean_box_uint32(locator[i]));
    }
    return locator_obj;
}

/* input: condition bits c */
/* output: support s */
void my_support_gen(gf * s, const unsigned char *c) {
	unsigned char L[ GFBITS ][ (1 << GFBITS)/8 ];
	for (int i = 0; i < GFBITS; i++)
		for (int j = 0; j < (1 << GFBITS)/8; j++)
			L[i][j] = 0;

	for (int i = 0; i < (1 << GFBITS); i++)
	{
		gf a = bitrev((gf) i);

		for (int j = 0; j < GFBITS; j++)
			L[j][ i/8 ] |= ((a >> j) & 1) << (i%8);
	}

	for (int j = 0; j < GFBITS; j++)
		apply_benes(L[j], c, 0);

	for (int i = 0; i < SYS_N; i++) {
		s[i] = 0;
		for (int j = GFBITS-1; j >= 0; j--)
		{
			s[i] <<= 1;
			s[i] |= (L[j][i/8] >> (i%8)) & 1;
		}
	}
}

extern "C" lean_obj_res lean_support_gen(b_lean_obj_arg sk_obj) {
    assert(lean_sarray_size(sk_obj) == COND_BYTES);
    const uint8_t* sk = lean_sarray_cptr(sk_obj);

	gf L[ SYS_N ];
	my_support_gen(L, sk);

    lean_obj_res L_obj = lean_alloc_array(SYS_N, SYS_N);
    for (size_t i = 0; i != SYS_N; ++i) {
        lean_array_set_core(L_obj, i, lean_box_uint32(L[i]));
    }
    return L_obj;
}

extern "C" lean_obj_res lean_elt_from_bytevec(b_lean_obj_arg w_obj, b_lean_obj_arg r_obj, b_lean_obj_arg x_obj) {
    if (LEAN_UNLIKELY(!lean_is_scalar(w_obj))) {
        lean_internal_panic_out_of_memory();
    }
    size_t w = lean_unbox(w_obj);

    if (LEAN_UNLIKELY(!lean_is_scalar(r_obj))) {
        lean_internal_panic_out_of_memory();
    }
    size_t r = lean_unbox(r_obj);
    assert(r == 8*w);

    assert(lean_sarray_size(x_obj) == w);
    const uint8_t* x = lean_sarray_cptr(x_obj);

    return nat_import_from_bytes(w, x);
}

extern "C" lean_obj_res lean_elt_to_bytevec(b_lean_obj_arg r_obj, b_lean_obj_arg w_obj, b_lean_obj_arg x) {
    if (LEAN_UNLIKELY(!lean_is_scalar(w_obj))) {
        lean_internal_panic_out_of_memory();
    }
    size_t w = lean_unbox(w_obj);

    lean_obj_res e_obj = lean_alloc_sarray1(1, w);
    nat_export_to_bytes(w, lean_sarray_cptr(e_obj), x);
    return e_obj;
}