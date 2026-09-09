## Profiling fatorial 4x2 de multiplicacao de matrizes

SSC0951 - Desenvolvimento de Codigo Otimizado

Planejamento fatorial completo com dois fatores e uma resposta de tempo mais
quatro contadores de hardware coletados com `perf`.

| Fator | Niveis |
|---|---|
| **Tecnica** | base, loop interchange, loop unrolling, loop tiling |
| **Alocacao** | estatica (array contiguo em `.bss`), dinamica (`int**`, um `malloc` por linha) |

### Mapa dos oito experimentos

| Binario | Tecnica | Alocacao | Kernel | Fonte dos kernels |
|---|---|---|---|---|
| `case1` | base | estatica | `multiplyMatrixStatic` | `utils_static.c` |
| `case2` | base | dinamica | `multiplyMatrix` | `utils.c` |
| `case3` | loop interchange | estatica | `loopInterchangeMultStatic` | `utils_static.c` |
| `case4` | loop interchange | dinamica | `loopInterchangeMult` | `utils.c` |
| `case5` | loop unrolling | estatica | `loopUnrollingMultStatic` | `utils_static.c` |
| `case6` | loop unrolling | dinamica | `loopUnrollingMult` | `utils.c` |
| `case7` | loop tiling | estatica | `loopTilingMultStatic` | `utils_static.c` |
| `case8` | loop tiling | dinamica | `loopTilingMult` | `utils.c` |

Impares sao estaticos, pares sao dinamicos. Os quatro nests de laco de
`utils_static.c` sao identicos caractere por caractere aos de `utils.c`: a
unica diferenca e o tipo do parametro, `int m[N][N]` contra `int **m`, e
portanto o enderecamento. Isso e exatamente o Fator 2 e nada mais.

### Parametros

Definidos uma unica vez em `matrix_config.h`. Nenhum `case*.c` e nenhum
`utils*.c` redefine `N`.

| Macro | Valor | Justificativa |
|---|---|---|
| `N` | 1000 | 3 matrizes de `int` = 11,44 MiB, muito acima da L3 de 12 MiB |
| `BLOCO` | 32 | L1d de 48 KiB. 3 tiles de 32x32 `int` ocupam 18,0 KiB por linha de cache, 37% da L1d. Com 64 seriam 60 KiB e estouraria |
| `UNROLL` | 4 | corta os branches do laco interno de ~1e9 para ~2,5e8, acima do ruido |
| `SEED_A`, `SEED_B` | 12345, 67890 | preenchimento deterministico e nao uniforme |
| `VALOR_MAX` | 255 | `\|c[i][j]\| <= N * 255^2 = 65025000`, cerca de 3% da faixa do `int` |

### Contrato do binario

Sem argumentos de linha de comando. Os oito binarios **sao** os oito pontos do
desenho e se autoidentificam, portanto o script de coleta nao consegue rotular
uma execucao errado passando a flag errada.

```
stdout: exatamente uma linha, sem cabecalho
  case_id,technique,allocation,n,block_size,unroll_factor,tempo_kernel_ns,checksum
stderr: apenas diagnostico
exit  : 0 em sucesso, diferente de zero em falha de alocacao
```

`tempo_kernel_ns` sao nanossegundos **inteiros**, medidos com
`clock_gettime(CLOCK_MONOTONIC)` imediatamente antes e depois da chamada do
kernel. Inteiro e nao ponto flutuante de proposito: nesta maquina
`LC_NUMERIC=pt_BR.UTF-8`, e sob esse locale o `printf` do bash rejeita
`1234.5` e imprime `1234,00`. Inteiro elimina a classe de bug inteira.

`n` vem de `matrixDim()`, implementada na biblioteca, e nao do macro `N` visto
por `main`. Assim o valor registrado nao pode mentir.

O preenchimento de A e B e a zeragem de C acontecem **antes** do relogio, e os
quatro kernels nao zeram C. Isso mantem fora da medicao o gerador
pseudoaleatorio e as faltas de pagina de primeiro toque, que diferem entre as
duas familias de alocacao e seriam cobradas do Fator 2 pelo motivo errado.

### Como rodar

```sh
# 1. compilar (8 binarios de medicao + 8 de verificacao)
make all verif

# 2. portao: provar que os oito kernels calculam a mesma matriz
bash experimento/verificar_matriz.sh

# 3. liberar os contadores do perf (uma vez por boot)
sudo sysctl -w kernel.perf_event_paranoid=1

# 4. coletar 8 celulas x 10 replicas = 80 medicoes (cerca de 8 minutos)
bash experimento/run_experimento.sh

# 5. analisar
Rscript analise/analise.R
```

O passo 2 e portao. Estatistica sobre kernels que calculam matrizes diferentes
nao vale nada, e o `md5sum` compara os 1.000.000 de elementos de C, nao apenas
um digest de 64 bits deles.

O passo 3 e obrigatorio. `perf_event_paranoid` acima de 1 bloqueia a abertura
dos contadores, e no Ubuntu o valor 3 ou mais bloqueia todo `perf_event_open`,
inclusive eventos de software. O script de coleta apenas verifica e aborta com
essa mensagem, nunca invoca `sudo`.

### Metricas coletadas

Tempo de resposta do kernel, `L1-dcache-loads`, `L1-dcache-load-misses`,
`branch-instructions`, `branch-misses`. Media e intervalo de confianca de 95%
em cada um dos oito experimentos.

Os eventos vao **qualificados por PMU** como `cpu_core/EVENTO/`. Esta maquina
e hibrida, e a secao INTEL HYBRID SUPPORT do `man perf-stat` diz que um evento
disponivel nos dois PMUs cria dois eventos automaticamente, um por PMU. Com
`taskset -c 0` o gemeo `cpu_atom` nunca e escalonado e retorna
`<not counted>`, que um parser ingenuo leria como zero. O script sonda a
nomenclatura, tem um conjunto de fallback com eventos nativos, e registra a
escolha e o mapeamento resolvido em `dados/eventos.txt`.

### Duas ANOVAs 2x2

| | Fatores cruzados | Resposta | Casos |
|---|---|---|---|
| Fatorial 1 | Alocacao x (base vs interchange) | taxa de miss de L1d | 1, 2, 3, 4 |
| Fatorial 2 | Alocacao x (base vs unrolling) | taxa de miss de branch | 1, 2, 5, 6 |

Os dois reusam os casos 1 e 2 como nivel base, portanto compartilham 20 das 40
observacoes e **nao sao estatisticamente independentes**. Isso e inerente ao
desenho pedido, mas os dois conjuntos de p-valores nao podem ser citados como
evidencia independente um do outro.

### Estrutura

```
matrix_config.h            N, BLOCO, UNROLL, sementes, o LCG compartilhado
utils.h / utils.c          kernels da familia dinamica (int**)
utils_static.h / .c        kernels da familia estatica (int m[N][N])
case1.c .. case8.c         as oito celulas do desenho
Makefile                   um unico CFLAGS para os oito binarios
experimento/
  run_experimento.sh       coleta: portoes, sondagem de evento, 80 execucoes
  verificar_matriz.sh      prova de equivalencia por md5sum
  extrai_perf.awk          parser de perf stat -x ';'
  ordem.awk                ordem de execucao randomizada com semente fixa
dados/                     dados_brutos.csv, ambiente.txt, eventos.txt, ...
analise/analise.R          descritiva, IC, as duas ANOVAs, pressupostos
figuras/                   11 figuras em PDF vetorial
```

### Controle de variabilidade

`-O0` obrigatorio, sem `-march=native`: em `-O0` o gcc nao vetoriza nem aplica
transformacao de laco, portanto as quatro variantes escritas a mao sao
genuinamente o que se mede. Execucoes fixadas em `cpu0` com `taskset`, um
aquecimento descartado por celula, e ordem de execucao randomizada com semente
fixa e persistida em `dados/ordem_execucao.txt`.

Limitacoes conhecidas e registradas em `dados/ambiente.txt`: governor
`powersave` com boost dinamico de 0,4 a 5,4 GHz, e SMT ativo, com `cpu1`
compartilhando a L1d de 48 KiB e o preditor de branch com a thread medida.
