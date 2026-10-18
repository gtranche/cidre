/* Banc « vrai code » x86-64 sous FEX (levier extensions ARM, tests/extensions_fex.sh) :
 * SQLite en memoire et zlib, sources de src/wine11/libs. Compilation :
 *   L=src/wine11/libs; x86_64-w64-mingw32-clang -O2 -w -Iinc -I$L/sqlite3 -I$L/zlib \
 *     -DSQLITE_THREADSAFE=0 -DSQLITE_OMIT_LOAD_EXTENSION -o banc_reel.exe tests/banc_reel_fex.c \
 *     $L/zlib/{adler32,crc32,deflate,inflate,inftrees,inffast,trees,zutil}.c
 * (inc/gzguts.h = fichier vide : la zlib de Wine n a pas les gz*).
 * M1 Max, FEX 0179, medianes de 7 passes : sqlite 1332 -> 1302 ms, zlib 354 -> 345 ms
 * avec lrcpc,lrcpc2,flagm,flagm2,frintts,fcma,dotprod ; LRCPC/LRCPC2 en font l essentiel. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <windows.h>
#include "sqlite3.c"
#include "zlib.h"

static double ms( LARGE_INTEGER a, LARGE_INTEGER b )
{
    LARGE_INTEGER f;
    QueryPerformanceFrequency( &f );
    return (b.QuadPart - a.QuadPart) * 1000.0 / f.QuadPart;
}

static int banc_sqlite( void )
{
    sqlite3 *db; sqlite3_stmt *st; long long s = 0; int i;
    sqlite3_open( ":memory:", &db );
    sqlite3_exec( db, "create table t(a integer primary key, b integer, c text); create index ib on t(b);", 0, 0, 0 );
    sqlite3_exec( db, "begin", 0, 0, 0 );
    sqlite3_prepare_v2( db, "insert into t(b,c) values(?,?)", -1, &st, 0 );
    for (i = 0; i < 200000; i++)
    {
        char txt[32];
        sprintf( txt, "ligne-%08x", (unsigned)(i * 2654435761u) );
        sqlite3_bind_int( st, 1, (int)((i * 7919u) % 100003) );
        sqlite3_bind_text( st, 2, txt, -1, SQLITE_TRANSIENT );
        sqlite3_step( st ); sqlite3_reset( st );
    }
    sqlite3_finalize( st );
    sqlite3_exec( db, "commit", 0, 0, 0 );
    sqlite3_prepare_v2( db, "select sum(a), count(*) from t where b between ? and ?", -1, &st, 0 );
    for (i = 0; i < 3000; i++)
    {
        sqlite3_bind_int( st, 1, i * 30 ); sqlite3_bind_int( st, 2, i * 30 + 200 );
        if (sqlite3_step( st ) == SQLITE_ROW) s += sqlite3_column_int64( st, 0 ) + sqlite3_column_int( st, 1 );
        sqlite3_reset( st );
    }
    sqlite3_finalize( st );
    sqlite3_prepare_v2( db, "select c from t order by c limit 1 offset 150000", -1, &st, 0 );
    if (sqlite3_step( st ) == SQLITE_ROW) s += sqlite3_column_bytes( st, 0 );
    sqlite3_finalize( st );
    sqlite3_close( db );
    printf( "somme %lld ", s );
    return 0;
}

static int banc_zlib( void )
{
    const size_t n = 8 << 20;
    unsigned char *src = malloc( n ), *dst = malloc( n + 1024 ), *ret = malloc( n );
    unsigned x = 1; size_t i; uLongf dl, rl; unsigned long crc;
    for (i = 0; i < n; i++)
    {
        x ^= x << 13; x ^= x >> 17; x ^= x << 5;
        src[i] = (i % 97 < 60) ? "le chat mange la souris "[i % 24] : (unsigned char)(x & 0x3f);
    }
    {
        z_stream z; memset( &z, 0, sizeof(z) );
        deflateInit( &z, 6 );
        z.next_in = src; z.avail_in = n; z.next_out = dst; z.avail_out = n + 1024;
        deflate( &z, Z_FINISH ); dl = z.total_out; deflateEnd( &z );
        memset( &z, 0, sizeof(z) );
        inflateInit( &z );
        z.next_in = dst; z.avail_in = dl; z.next_out = ret; z.avail_out = n;
        inflate( &z, Z_FINISH ); rl = z.total_out; inflateEnd( &z );
    }
    crc = crc32( 0, ret, rl );
    printf( "somme %lu/%lu/%lx ", (unsigned long)dl, (unsigned long)rl, crc );
    return memcmp( src, ret, n ) != 0;
}

int main( int argc, char **argv )
{
    const char *mode = argc > 1 ? argv[1] : "sqlite";
    LARGE_INTEGER a, b; int r;
    QueryPerformanceCounter( &a );
    r = !strcmp( mode, "zlib" ) ? banc_zlib() : banc_sqlite();
    QueryPerformanceCounter( &b );
    printf( "%s : %.1f ms\n", mode, ms( a, b ) );
    return r;
}
