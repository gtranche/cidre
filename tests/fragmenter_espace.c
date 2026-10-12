/* Bibliotheque a inserer (DYLD_INSERT_LIBRARIES) qui met un processus dans
 * l'etat ou macOS 27 met un jeu apres quelques minutes : l'espace d'adresses
 * au-dessus de 4 Gio sature de regions de l'hote, sans trou d'un megaoctet.
 * Releve sur un Mac M4 (Expedition 33, DXMT, vmmap) : [4 Gio, 6 Gio) occupe a
 * 95 % par 6697 regions, puis le cache partage du systeme de 6 a 13,4 Gio.
 *
 * Le constructeur tourne avant le main de Wine. Il pose une page inaccessible
 * tous les FRAGMENTER_PAS_KIO (1024 par defaut) de 4 Gio a 4 Gio +
 * FRAGMENTER_GIO, sans rien ecraser : ce qui est deja pris est laisse.
 * FRAGMENTER_HAUT sature de la meme facon [3 Tio, 3 Tio + 1 Gio), une zone
 * vide ou sonde_fils.exe sait d'avance quelle adresse une recherche bornee
 * doit rendre. Sans ces variables il ne fait rien.
 *
 *   cc -dynamiclib -o fragmenter_espace.dylib fragmenter_espace.c */
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static void poser( mach_vm_address_t debut, mach_vm_address_t fin, mach_vm_size_t pas, const char *quoi )
{
    mach_vm_size_t page = (mach_vm_size_t)getpagesize();
    unsigned long posees = 0, prises = 0;
    mach_vm_address_t a;

    for (a = debut; a < fin; a += pas)
    {
        mach_vm_address_t ou = a;

        if (mach_vm_map( mach_task_self(), &ou, page, 0, VM_FLAGS_FIXED, MEMORY_OBJECT_NULL, 0, 0,
                         VM_PROT_NONE, VM_PROT_NONE, VM_INHERIT_COPY )) prises++;
        else posees++;
    }
    if (getenv( "FRAGMENTER_BAVARD" ))
        fprintf( stderr, "fragmenter_espace[%d] %s : %lu pages posees de %#llx a %#llx, %lu adresses deja prises\n",
                 getpid(), quoi, posees, debut, fin, prises );
}

__attribute__((constructor)) static void fragmenter(void)
{
    const char *gio = getenv( "FRAGMENTER_GIO" ), *pas_kio = getenv( "FRAGMENTER_PAS_KIO" );
    mach_vm_size_t pas = (pas_kio ? strtoull( pas_kio, NULL, 0 ) : 1024) << 10;

    if (!pas) return;
    if (gio && atof( gio ) > 0)
        poser( 0x100000000ull, 0x100000000ull + (mach_vm_address_t)(atof( gio ) * (double)(1ull << 30)), pas, "bas" );
    if (getenv( "FRAGMENTER_HAUT" ))
        poser( 0x30000000000ull, 0x30000000000ull + (1ull << 30), 1 << 20, "haut" );
}
