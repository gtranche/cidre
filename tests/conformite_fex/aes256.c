/* Teste AES-256-CBC multi-blocs sous FEX (vecteur NIST SP800-38A).
   key=603deb..dff4  IV=000102..0f
   pt = 6bc1bee2.. ae2d8a57.. 30c81c46.. f69f2445..
   ct = f58c4c04d6e5f1ba779eabfb5f7bfbd6 9cfc4e967edb808d679f777bc6702c7d
        39f23369a9d9bacfa530e26304231461 b2eb05e2c39be9fcda6c19078c6a9d1b */
#include <wmmintrin.h>
#include <emmintrin.h>
typedef unsigned int DWORD; typedef unsigned char u8;
__declspec(dllimport) void ExitProcess(DWORD);
__declspec(dllimport) void *GetStdHandle(DWORD);
__declspec(dllimport) int WriteFile(void*,const void*,DWORD,DWORD*,void*);
static void dire(const char*s){DWORD n=0,l=0;while(s[l])l++;WriteFile(GetStdHandle((DWORD)-11),s,l,&n,0);}
static void hx(const u8*p,int n){char b[80];const char*h="0123456789abcdef";int i;for(i=0;i<n;i++){b[2*i]=h[p[i]>>4];b[2*i+1]=h[p[i]&15];}b[2*n]=0;dire(b);}
int _fltused=0;
static __m128i ex1(__m128i k,__m128i a){a=_mm_shuffle_epi32(a,0xff);k=_mm_xor_si128(k,_mm_slli_si128(k,4));k=_mm_xor_si128(k,_mm_slli_si128(k,4));k=_mm_xor_si128(k,_mm_slli_si128(k,4));return _mm_xor_si128(k,a);}
static __m128i ex2(__m128i k,__m128i k2){__m128i a=_mm_shuffle_epi32(_mm_aeskeygenassist_si128(k2,0),0xaa);k=_mm_xor_si128(k,_mm_slli_si128(k,4));k=_mm_xor_si128(k,_mm_slli_si128(k,4));k=_mm_xor_si128(k,_mm_slli_si128(k,4));return _mm_xor_si128(k,a);}
void mainCRTStartup(void){
  static const u8 K[32]={0x60,0x3d,0xeb,0x10,0x15,0xca,0x71,0xbe,0x2b,0x73,0xae,0xf0,0x85,0x7d,0x77,0x81,0x1f,0x35,0x2c,0x07,0x3b,0x61,0x08,0xd7,0x2d,0x98,0x10,0xa3,0x09,0x14,0xdf,0xf4};
  static const u8 IV[16]={0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15};
  static const u8 PT[64]={0x6b,0xc1,0xbe,0xe2,0x2e,0x40,0x9f,0x96,0xe9,0x3d,0x7e,0x11,0x73,0x93,0x17,0x2a,0xae,0x2d,0x8a,0x57,0x1e,0x03,0xac,0x9c,0x9e,0xb7,0x6f,0xac,0x45,0xaf,0x8e,0x51,0x30,0xc8,0x1c,0x46,0xa3,0x5c,0xe4,0x11,0xe5,0xfb,0xc1,0x19,0x1a,0x0a,0x52,0xef,0xf6,0x9f,0x24,0x45,0xdf,0x4f,0x9b,0x17,0xad,0x2b,0x41,0x7b,0xe6,0x6c,0x37,0x10};
  __m128i rk[15];
  rk[0]=_mm_loadu_si128((__m128i*)K); rk[1]=_mm_loadu_si128((__m128i*)(K+16));
  rk[2]=ex1(rk[0],_mm_aeskeygenassist_si128(rk[1],0x01)); rk[3]=ex2(rk[1],rk[2]);
  rk[4]=ex1(rk[2],_mm_aeskeygenassist_si128(rk[3],0x02)); rk[5]=ex2(rk[3],rk[4]);
  rk[6]=ex1(rk[4],_mm_aeskeygenassist_si128(rk[5],0x04)); rk[7]=ex2(rk[5],rk[6]);
  rk[8]=ex1(rk[6],_mm_aeskeygenassist_si128(rk[7],0x08)); rk[9]=ex2(rk[7],rk[8]);
  rk[10]=ex1(rk[8],_mm_aeskeygenassist_si128(rk[9],0x10)); rk[11]=ex2(rk[9],rk[10]);
  rk[12]=ex1(rk[10],_mm_aeskeygenassist_si128(rk[11],0x20)); rk[13]=ex2(rk[11],rk[12]);
  rk[14]=ex1(rk[12],_mm_aeskeygenassist_si128(rk[13],0x40));
  __m128i prev=_mm_loadu_si128((__m128i*)IV); u8 out[64]; int b,i;
  for(b=0;b<4;b++){
    __m128i m=_mm_xor_si128(_mm_loadu_si128((__m128i*)(PT+16*b)),prev);
    m=_mm_xor_si128(m,rk[0]);
    for(i=1;i<14;i++)m=_mm_aesenc_si128(m,rk[i]);
    m=_mm_aesenclast_si128(m,rk[14]);
    _mm_storeu_si128((__m128i*)(out+16*b),m); prev=m;
  }
  dire("AES256-CBC ct = ");hx(out,64);dire("\n");
  dire("attendu       = f58c4c04d6e5f1ba779eabfb5f7bfbd69cfc4e967edb808d679f777bc6702c7d39f23369a9d9bacfa530e26304231461b2eb05e2c39be9fcda6c19078c6a9d1b\n");
  static const u8 E[16]={0xf5,0x8c,0x4c,0x04,0xd6,0xe5,0xf1,0xba,0x77,0x9e,0xab,0xfb,0x5f,0x7b,0xfb,0xd6};
  int ok=1;for(i=0;i<16;i++)if(out[i]!=E[i])ok=0;
  dire(ok?"AES-256-CBC : CORRECT\n":"AES-256-CBC : FAUX (bug FEX)\n");
  ExitProcess(0);
}
