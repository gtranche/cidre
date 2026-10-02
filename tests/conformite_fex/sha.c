/* Teste SHA-NI emule par FEX : SHA-256("abc") attendu
   ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad */
#include <immintrin.h>
typedef unsigned int DWORD; typedef unsigned char u8; typedef unsigned int u32;
__declspec(dllimport) void ExitProcess(DWORD);
__declspec(dllimport) void *GetStdHandle(DWORD);
__declspec(dllimport) int WriteFile(void*,const void*,DWORD,DWORD*,void*);
static void dire(const char*s){DWORD n=0,l=0;while(s[l])l++;WriteFile(GetStdHandle((DWORD)-11),s,l,&n,0);}
static void hx(const u8*p,int n){char b[80];const char*h="0123456789abcdef";int i;for(i=0;i<n;i++){b[2*i]=h[p[i]>>4];b[2*i+1]=h[p[i]&15];}b[2*n]=0;dire(b);}
int _fltused=0;
static const u32 K[64]={
0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2};
void mainCRTStartup(void){
    /* message "abc" + padding sur 1 bloc de 64 octets */
    u8 blk[64]={0}; blk[0]='a';blk[1]='b';blk[2]='c';blk[3]=0x80; blk[63]=0x18;
    __m128i MASK=_mm_set_epi64x(0x0c0d0e0f08090a0bULL,0x0405060700010203ULL);
    __m128i S0=_mm_set_epi32(0xa54ff53a,0x3c6ef372,0xbb67ae85,0x6a09e667);
    __m128i S1=_mm_set_epi32(0x5be0cd19,0x1f83d9ab,0x9b05688c,0x510e527f);
    __m128i TMP=_mm_shuffle_epi32(S0,0xB1),T2=_mm_shuffle_epi32(S1,0x1B);
    __m128i STATE0=_mm_alignr_epi8(TMP,T2,8);
    __m128i STATE1=_mm_blend_epi16(T2,TMP,0xF0);
    __m128i AB=STATE0,CD=STATE1;
    __m128i M[4],MSG,T;
    for(int i=0;i<4;i++)M[i]=_mm_shuffle_epi8(_mm_loadu_si128((__m128i*)(blk+16*i)),MASK);
    #define RND(i,m) MSG=_mm_add_epi32(m,_mm_set_epi32(K[i*4+3],K[i*4+2],K[i*4+1],K[i*4+0]));\
        STATE1=_mm_sha256rnds2_epu32(STATE1,STATE0,MSG);MSG=_mm_shuffle_epi32(MSG,0x0E);\
        STATE0=_mm_sha256rnds2_epu32(STATE0,STATE1,MSG);
    __m128i m0=M[0],m1=M[1],m2=M[2],m3=M[3];
    RND(0,m0);RND(1,m1);RND(2,m2);RND(3,m3);
    m0=_mm_sha256msg1_epu32(m0,m1);m0=_mm_add_epi32(m0,_mm_alignr_epi8(m3,m2,4));m0=_mm_sha256msg2_epu32(m0,m3);RND(4,m0);
    m1=_mm_sha256msg1_epu32(m1,m2);m1=_mm_add_epi32(m1,_mm_alignr_epi8(m0,m3,4));m1=_mm_sha256msg2_epu32(m1,m0);RND(5,m1);
    m2=_mm_sha256msg1_epu32(m2,m3);m2=_mm_add_epi32(m2,_mm_alignr_epi8(m1,m0,4));m2=_mm_sha256msg2_epu32(m2,m1);RND(6,m2);
    m3=_mm_sha256msg1_epu32(m3,m0);m3=_mm_add_epi32(m3,_mm_alignr_epi8(m2,m1,4));m3=_mm_sha256msg2_epu32(m3,m2);RND(7,m3);
    m0=_mm_sha256msg1_epu32(m0,m1);m0=_mm_add_epi32(m0,_mm_alignr_epi8(m3,m2,4));m0=_mm_sha256msg2_epu32(m0,m3);RND(8,m0);
    m1=_mm_sha256msg1_epu32(m1,m2);m1=_mm_add_epi32(m1,_mm_alignr_epi8(m0,m3,4));m1=_mm_sha256msg2_epu32(m1,m0);RND(9,m1);
    m2=_mm_sha256msg1_epu32(m2,m3);m2=_mm_add_epi32(m2,_mm_alignr_epi8(m1,m0,4));m2=_mm_sha256msg2_epu32(m2,m1);RND(10,m2);
    m3=_mm_sha256msg1_epu32(m3,m0);m3=_mm_add_epi32(m3,_mm_alignr_epi8(m2,m1,4));m3=_mm_sha256msg2_epu32(m3,m2);RND(11,m3);
    m0=_mm_sha256msg1_epu32(m0,m1);m0=_mm_add_epi32(m0,_mm_alignr_epi8(m3,m2,4));m0=_mm_sha256msg2_epu32(m0,m3);RND(12,m0);
    m1=_mm_sha256msg1_epu32(m1,m2);m1=_mm_add_epi32(m1,_mm_alignr_epi8(m0,m3,4));m1=_mm_sha256msg2_epu32(m1,m0);RND(13,m1);
    m2=_mm_sha256msg1_epu32(m2,m3);m2=_mm_add_epi32(m2,_mm_alignr_epi8(m1,m0,4));m2=_mm_sha256msg2_epu32(m2,m1);RND(14,m2);
    m3=_mm_sha256msg1_epu32(m3,m0);m3=_mm_add_epi32(m3,_mm_alignr_epi8(m2,m1,4));m3=_mm_sha256msg2_epu32(m3,m2);RND(15,m3);
    STATE0=_mm_add_epi32(STATE0,AB);STATE1=_mm_add_epi32(STATE1,CD);
    TMP=_mm_shuffle_epi32(STATE0,0x1B);T2=_mm_shuffle_epi32(STATE1,0xB1);
    STATE0=_mm_blend_epi16(TMP,T2,0xF0);STATE1=_mm_alignr_epi8(T2,TMP,8);
    u8 out[32];
    _mm_storeu_si128((__m128i*)out,_mm_shuffle_epi8(STATE0,MASK));
    _mm_storeu_si128((__m128i*)(out+16),_mm_shuffle_epi8(STATE1,MASK));
    dire("SHA-256(abc)= ");hx(out,32);dire("\n");
    dire("attendu     = ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\n");
    static const char*E="ba7816bf"; dire(out[0]==0xba&&out[1]==0x78&&out[2]==0x16&&out[3]==0xbf?"SHA-NI : CORRECT\n":"SHA-NI : FAUX (bug FEX)\n");
    ExitProcess(0);
}
