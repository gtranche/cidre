# Conformité FEX

Petits programmes x86-64 Windows qui vérifient que **FEX émule correctement** les instructions et
mécanismes dont dépendent les vrais jeux. Lanceur : `../conformite_fex.sh`.

Origine : pendant l'enquête sur Dead by Daylight, il a fallu prouver que la pile (FEX + Wine) ne
corrompait rien. Chaque hypothèse a été testée en isolation — et **toutes passent**. Ça a aussi
rattrapé un bug de mon propre test SHA (état initial rangé en ordre de voie inverse), d'où la règle :
un test qui dit « FEX est faux » doit d'abord se prouver correct sur du vrai matériel / un vecteur connu.

À relancer après toute reconstruction de FEX (`0070`/`0076`/etc.) pour attraper une régression.

| Test | Instruction / mécanisme | Pourquoi ça compte |
|---|---|---|
| `sha.c` | SHA-NI (SHA256RNDS2/MSG1/MSG2), vecteur NIST « abc » | hachage des jeux ; OpenSSL embarqué |
| `aes256.c` | AES-NI (AESENC…), AES-256-CBC vecteur NIST | déchiffrement (sauvegardes, assets) |
| `bignum.c` | MUL, MULX, ADCX (64×64→128, retenue) | fondation RSA/EC (signatures) |
| `adox.c` | ADOX + double chaîne de retenue ADCX/ADOX | cœur du multiply grands entiers (RSA/EC) |
| `tso_mp.c` | Ordre mémoire x86 (litmus message-passing) | TSO : init de singletons inter-thread |
| `smc.c` | Code auto-modifiant (patch + réexécution) | anti-tamper ; lié à `FEX_SMCCHECKS` |
| `tls_callbacks.c` | Callbacks TLS (DLL_PROCESS/THREAD_ATTACH) | init par thread du CRT MSVC |
| `static_msvc.c` | Static thread-safe MSVC (époque `_Init_thread_epoch`) | statics locaux omniprésents en C++ |

Chaque programme imprime un marqueur (`... CORRECT` / `... OK`) ou un marqueur d'échec. Le lanceur
compile avec llvm-mingw, exécute sous `etape2_pile_arm64ec.sh`, et compte les OK.

Note SMC : `smc.c` montre que le SMC **simple** est bien détecté par FEX (défaut `mtrack`). L'anti-tamper
de DbD en fait un plus subtil que `mtrack` rate ; voir `FEX_SMCCHECKS=full` (doc DbD). `smc.c` doit
utiliser un appel **indirect volatile** (sinon le compilateur replie la fonction en constante et le
test est faux — piège rencontré).
