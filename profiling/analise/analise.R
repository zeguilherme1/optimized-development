# =============================================================================
# analise.R - analise estatistica do planejamento fatorial 4x2
#
# SSC0951 - Desenvolvimento de Codigo Otimizado
#
# Fator 1 Tecnica  : base, interchange, unrolling, tiling
# Fator 2 Alocacao : estatica, dinamica
#
# Entrada : dados/dados_brutos.csv
# Saidas  : analise/resultados.txt
#           figuras/*.pdf
#           analise/tex/*.tex   (tabelas e macros para o relatorio)
#
# Usa apenas R base e o pacote stats. ggplot2 e dplyr nao estao instalados.
# car e lmtest estao instalados, mas este script nao depende deles: todo teste
# usado aqui tem equivalente em stats.
# =============================================================================

# Descoberta do diretorio raiz do projeto (funciona via Rscript)
args <- commandArgs(trailingOnly = FALSE)
arq  <- sub("^--file=", "", args[grep("^--file=", args)])
raiz <- normalizePath(file.path(dirname(arq), ".."))

dir_dados   <- file.path(raiz, "dados")
dir_figuras <- file.path(raiz, "figuras")
dir_tex     <- file.path(raiz, "analise", "tex")
dir.create(dir_figuras, showWarnings = FALSE)
dir.create(dir_tex,     showWarnings = FALSE)

saida <- file.path(raiz, "analise", "resultados.txt")
con   <- file(saida, "w")

emitir <- function(...) {
  linhas <- unlist(list(...))
  cat(linhas, sep = "\n", file = con, append = TRUE)
  cat(linhas, sep = "\n")
}
titulo <- function(txt) {
  emitir("", strrep("=", 78), txt, strrep("=", 78))
}
subtitulo <- function(txt) {
  emitir("", txt, strrep("-", nchar(txt)))
}
tabela <- function(df) {
  txt <- capture.output(print(df, row.names = FALSE))
  emitir(txt)
}

# Formatacao numerica no padrao brasileiro, para o LaTeX
fmt <- function(x, d = 2) {
  trimws(formatC(x, format = "f", digits = d, big.mark = ".", decimal.mark = ","))
}
fmtm <- function(x, d = 2) {
  paste0("$", gsub(",", "{,}", fmt(x, d), fixed = TRUE), "$")
}
# Notacao cientifica em modo matematico. Necessaria porque os efeitos do
# Fatorial 2 sao da ordem de 1e-12 e fmt() com 6 casas os imprimiria como zero.
fmtsci <- function(x, d = 3) {
  if (length(x) != 1) return(sapply(x, fmtsci, d = d))
  if (!is.finite(x) || x == 0) return("$0$")
  e <- floor(log10(abs(x)))
  m <- x / 10^e
  if (e >= -3 && e <= 4) return(fmtm(x, max(0, d - e)))
  sprintf("$%s\\times10^{%d}$", gsub(",", "{,}", fmt(m, d), fixed = TRUE), e)
}

fmt_p <- function(p) {
  ifelse(p < 2e-16, "$<2\\times10^{-16}$",
         ifelse(p < 1e-4, sprintf("$%.1f\\times10^{%d}$",
                                  p / 10^floor(log10(p)), floor(log10(p))),
                fmtm(p, 4)))
}
macro <- function(nome, valor) {
  valor <- gsub(",", "{,}", as.character(valor), fixed = TRUE)
  sprintf("\\newcommand{\\%s}{%s}", nome, valor)
}
macros <- character(0)
add_macro <- function(nome, valor) {
  macros <<- c(macros, macro(nome, valor))
  invisible(NULL)
}
escrever_tabela <- function(linhas, arquivo) {
  n <- length(linhas)
  linhas[n] <- sub("[[:space:]]*\\\\\\\\[[:space:]]*$", "", linhas[n])
  writeLines(linhas, file.path(dir_tex, arquivo))
}

cinza <- "#666666"; azul <- "#1F4E79"; verm <- "#C00000"; verde <- "#2E7D32"
claro <- "#D6E4F0"

# =============================================================================
# 1. Leitura e integridade
# =============================================================================
titulo("1. LEITURA E VERIFICACAO DE INTEGRIDADE")

dados <- read.csv(file.path(dir_dados, "dados_brutos.csv"), dec = ".")

r        <- min(table(dados$caso))
n_casos  <- length(unique(dados$caso))
n_total  <- nrow(dados)

# Execucoes em que o tempo de CPU ficou abaixo do tempo de parede do kernel,
# ou seja o processo foi desescalonado durante a medicao. Nao invalida a
# medicao, mas e ruido de sistema que vale quantificar.
desescalonado <- sum(dados$perf_task_clock_ms * 1e6 < dados$tempo_kernel_ns * 0.98)

emitir(sprintf("Medicoes                          : %d", n_total))
emitir(sprintf("Celulas do planejamento           : %d", n_casos))
emitir(sprintf("Replicas por celula               : %d", r))
emitir(sprintf("Checksums distintos               : %d", length(unique(dados$checksum))))
emitir(sprintf("Valor do checksum                 : %s", format(dados$checksum[1], scientific = FALSE)))
emitir(sprintf("Ordem da matriz (n) distinta      : %d valor(es), n = %d",
               length(unique(dados$n)), dados$n[1]))
emitir(sprintf("Escala minima de contador (%%)     : %.2f", min(dados$perf_escala_min_pct)))
emitir(sprintf("Retentativas totais               : %d", sum(dados$retentativas)))
emitir(sprintf("Execucoes com CPU < parede        : %d de %d (processo desescalonado)",
               desescalonado, n_total))

stopifnot(n_casos == 8)
stopifnot(all(table(dados$caso) == r))
stopifnot(length(unique(dados$checksum)) == 1)
stopifnot(length(unique(dados$n)) == 1)
stopifnot(all(dados$perf_escala_min_pct >= 99.99))
stopifnot(all(dados$l1d_load_misses <= dados$l1d_loads))
stopifnot(all(dados$branch_misses <= dados$branch_instructions))
# O tempo do kernel vem de CLOCK_MONOTONIC (parede) e precisa caber no wall
# clock do processo. Comparar com task-clock seria premissa errada: task-clock
# e tempo de CPU, e se o processo for desescalonado durante o kernel o relogio
# de parede corre e o de CPU nao.
stopifnot(all(dados$tempo_kernel_ns <= dados$perf_duration_ns * 1.02))
# task-clock e duration_time vem de mecanismos diferentes, contabilidade do
# escalonador contra medicao da ferramenta, logo comparam-se apenas com folga.
stopifnot(all(dados$perf_duration_ns >= dados$perf_task_clock_ms * 1e6 * 0.98))

emitir("",
  "Um unico valor de checksum nas 80 medicoes comprova que as oito variantes",
  "de codigo calculam exatamente o mesmo produto matricial, portanto a",
  "comparacao entre celulas e valida. A prova independente e mais forte esta",
  "em dados/verificacao_matriz.txt, que compara o md5sum dos 1.000.000 de",
  "elementos de C e nao apenas um digest de 64 bits deles.",
  "",
  "Escala de contador em 100% em todas as linhas comprova que nenhum valor",
  "sofreu multiplexacao. Um contador multiplexado e escalado pelo perf e o",
  "numero resultante e extrapolacao, nao medicao.")

# =============================================================================
# 2. Colunas derivadas e fatores
# =============================================================================
titulo("2. COLUNAS DERIVADAS")

dados$tempo_ms         <- dados$tempo_kernel_ns / 1e6
dados$taxa_l1d_miss    <- dados$l1d_load_misses / dados$l1d_loads
dados$taxa_branch_miss <- dados$branch_misses / dados$branch_instructions

emitir("As taxas nascem aqui e nao no shell. O arquivo bruto guarda apenas",
       "medicao, e assim mudar a definicao de uma taxa e uma linha em R em vez",
       "de uma recoleta de 8 minutos. As taxas ficam como fracao em (0,1) e nao",
       "como percentual, para a transformacao logit se aplicar sem reescalar.")

niveis_tec <- c("base", "interchange", "unrolling", "tiling")
dados$fTec  <- factor(dados$tecnica, levels = niveis_tec)
dados$fAloc <- factor(dados$alocacao, levels = c("estatica", "dinamica"))
dados$rotulo <- sprintf("c%d %s/%s", dados$caso,
                        substr(dados$tecnica, 1, 5),
                        substr(dados$alocacao, 1, 3))

ordem_casos <- order(unique(dados$caso))
rot_caso <- tapply(dados$rotulo, dados$caso, function(v) v[1])

# =============================================================================
# 3. Estatistica descritiva e intervalo de confiança de 95%
# =============================================================================
titulo("3. ESTATISTICA DESCRITIVA E IC 95% POR EXPERIMENTO")

t_celula <- qt(0.975, r - 1)
emitir(sprintf("t(0,975; %d) usado no IC por celula : %.6f", r - 1, t_celula))
emitir("",
  "O enunciado pede media e IC de 95% para cada metrica em cada um dos oito",
  "experimentos, portanto o intervalo e o t por celula, media +- t*s/sqrt(n),",
  "com n = 10 e 9 graus de liberdade. Um intervalo com MSE agrupado seria mais",
  "estreito, porem valido apenas sob homocedasticidade, que a secao 7 rejeita.",
  "As figuras usam o intervalo por celula.")

resumir <- function(coluna) {
  ag <- aggregate(dados[[coluna]],
                  by = list(caso = dados$caso, tecnica = dados$tecnica,
                            alocacao = dados$alocacao),
                  FUN = function(v) {
                    n <- length(v); m <- mean(v); s <- sd(v)
                    meia <- qt(0.975, n - 1) * s / sqrt(n)
                    c(n = n, media = m, sd = s, cv = 100 * s / m, meia = meia,
                      ic_inf = m - meia, ic_sup = m + meia,
                      mediana = median(v), min = min(v), max = max(v))
                  })
  out <- data.frame(ag[, 1:3], ag$x)
  out <- out[order(out$caso), ]
  rownames(out) <- NULL
  out
}

respostas <- list(
  tempo_ms            = list(rot = "Tempo do kernel (ms)",          d = 2),
  l1d_loads           = list(rot = "L1-dcache-loads",               d = 0),
  l1d_load_misses     = list(rot = "L1-dcache-load-misses",         d = 0),
  branch_instructions = list(rot = "branch-instructions",           d = 0),
  branch_misses       = list(rot = "branch-misses",                 d = 0),
  taxa_l1d_miss       = list(rot = "Taxa de miss de L1d (fracao)",  d = 6),
  taxa_branch_miss    = list(rot = "Taxa de miss de branch (frac.)",d = 6)
)

desc <- list()
for (nm in names(respostas)) {
  d <- respostas[[nm]]$d
  s <- resumir(nm)
  desc[[nm]] <- s
  subtitulo(sprintf("3.%d %s", which(names(respostas) == nm), respostas[[nm]]$rot))
  tabela(data.frame(
    caso     = s$caso,
    tecnica  = s$tecnica,
    aloc     = s$alocacao,
    media    = signif(s$media, 7),
    sd       = signif(s$sd, 4),
    cv_pct   = round(s$cv, 3),
    ic_inf   = signif(s$ic_inf, 7),
    ic_sup   = signif(s$ic_sup, 7),
    min      = signif(s$min, 7),
    max      = signif(s$max, 7)
  ))
}

subtitulo("3.8 Coeficiente de variacao, panorama")
cv_tab <- data.frame(
  resposta = names(respostas),
  cv_min   = sapply(desc, function(s) round(min(s$cv), 4)),
  cv_max   = sapply(desc, function(s) round(max(s$cv), 4))
)
rownames(cv_tab) <- NULL
tabela(cv_tab)
emitir("",
  "Os contadores l1d_loads e branch_instructions sao funcao praticamente",
  "deterministica do fluxo de instrucoes executado, e o CV baixissimo deles",
  "confirma isso. A consequencia estatistica esta na secao 7: com resposta",
  "quase deterministica o MSE fica minusculo, o F fica enorme e todo p-valor",
  "sai abaixo de 2e-16. Significancia passa a ser garantida e portanto nao",
  "informativa, e o que interpreta o experimento e o tamanho de efeito e a",
  "alocacao percentual de variacao, nao a rejeicao de hipotese nula.")

# =============================================================================
# 4. Os dois subconjuntos 2x2
# =============================================================================
titulo("4. DEFINICAO DOS DOIS SUBCONJUNTOS 2x2")

sub1 <- dados[!is.na(dados$B_fat1), ]   # casos 1,2 base e 3,4 interchange
sub2 <- dados[!is.na(dados$B_fat2), ]   # casos 1,2 base e 5,6 unrolling

stopifnot(nrow(sub1) == 4 * r, nrow(sub2) == 4 * r)
stopifnot(all(table(sub1$A_alocacao, sub1$B_fat1) == r))
stopifnot(all(table(sub2$A_alocacao, sub2$B_fat2) == r))
stopifnot(identical(sort(unique(sub1$caso)), c(1L, 2L, 3L, 4L)))
stopifnot(identical(sort(unique(sub2$caso)), c(1L, 2L, 5L, 6L)))

emitir(sprintf("Fatorial 1 (cache) : casos %s, %d linhas, resposta taxa_l1d_miss",
               paste(sort(unique(sub1$caso)), collapse = ","), nrow(sub1)))
emitir(sprintf("Fatorial 2 (branch): casos %s, %d linhas, resposta taxa_branch_miss",
               paste(sort(unique(sub2$caso)), collapse = ","), nrow(sub2)))
emitir("Codificacao: A_alocacao -1 estatica, +1 dinamica.",
       "             B -1 base, +1 a tecnica sob teste.")
emitir("",
  "Declaracao necessaria: os dois fatoriais reusam os casos 1 e 2 como nivel",
  "base, portanto compartilham 20 das 40 observacoes e NAO sao estatisticamente",
  "independentes. Isso e inerente ao desenho pedido pela atividade e nao um",
  "erro, mas os dois conjuntos de p-valores nao podem ser citados como",
  "evidencia independente um do outro.")

# =============================================================================
# 5. Motor fatorial 2x2: matriz de sinais e aov(), com provas mutuas
# =============================================================================
fatorial2x2 <- function(d, resp, colB, rot_b) {
  nc <- 4
  y  <- d[[resp]]
  A  <- d$A_alocacao
  B  <- d[[colB]]

  m <- aggregate(list(y = y), by = list(A = A, B = B), FUN = mean)
  m <- m[order(m$B, m$A), ]

  X <- cbind(I = 1, A = m$A, B = m$B, AB = m$A * m$B)
  stopifnot(max(abs(crossprod(X) - diag(nc) * nc)) < 1e-12)   # ortogonalidade

  q <- as.numeric(t(X) %*% m$y) / nc
  names(q) <- colnames(X)

  ss_ef  <- nc * r * q[-1]^2
  cel    <- setNames(m$y, paste(m$A, m$B))
  ss_err <- sum((y - cel[paste(A, B)])^2)
  ss_tot <- sum((y - mean(y))^2)
  gl_err <- nc * (r - 1)
  mse    <- ss_err / gl_err
  se_q   <- sqrt(mse / (nc * r))
  tc     <- qt(0.975, gl_err)

  d2 <- d
  d2$fA <- factor(A, levels = c(-1, 1), labels = c("estatica", "dinamica"))
  d2$fB <- factor(B, levels = c(-1, 1), labels = c("base", rot_b))
  mod <- aov(as.formula(sprintf("%s ~ fA * fB", resp)), data = d2)
  tab <- summary(mod)[[1]]

  # prova 1: matriz de sinais bate com aov()
  stopifnot(max(abs(as.numeric(ss_ef) - tab[1:3, "Sum Sq"])) < 1e-8 * ss_tot)
  # prova 2: aditividade das somas de quadrados
  stopifnot(abs(sum(ss_ef) + ss_err - ss_tot) < 1e-8 * ss_tot)
  # prova 3: rota independente pelas medias marginais
  ss_A_marg <- 2 * r * sum((tapply(y, A, mean) - mean(y))^2)
  ss_B_marg <- 2 * r * sum((tapply(y, B, mean) - mean(y))^2)
  stopifnot(abs(ss_A_marg - ss_ef[["A"]]) < 1e-8 * ss_tot)
  stopifnot(abs(ss_B_marg - ss_ef[["B"]]) < 1e-8 * ss_tot)

  pct <- 100 * c(ss_ef, Erro = ss_err) / ss_tot
  stopifnot(abs(sum(pct) - 100) < 1e-8)

  list(resp = resp, rot_b = rot_b, q = q, ss = ss_ef, ss_err = ss_err,
       ss_tot = ss_tot, gl_err = gl_err, mse = mse, se_q = se_q, tc = tc,
       pct = pct, mod = mod, anova = tab, medias = m, dados = d2, y = y,
       A = A, B = B)
}

relatar_fatorial <- function(f, num, nome, unidade) {
  titulo(sprintf("%d. FATORIAL %s: Alocacao x %s, resposta %s",
                 num, num - 5, f$rot_b, f$resp))

  subtitulo(sprintf("%d.1 Medias das quatro celulas (%s)", num, unidade))
  tabela(data.frame(
    A_alocacao = f$medias$A,
    alocacao   = ifelse(f$medias$A == 1, "dinamica", "estatica"),
    B          = f$medias$B,
    tecnica    = ifelse(f$medias$B == 1, f$rot_b, "base"),
    media      = signif(f$medias$y, 7)
  ))

  subtitulo(sprintf("%d.2 Coeficientes do modelo e IC 95%%", num))
  ic_inf <- f$q[-1] - f$tc * f$se_q
  ic_sup <- f$q[-1] + f$tc * f$se_q
  signif_ef <- (ic_inf > 0) | (ic_sup < 0)
  emitir(sprintf("q0 (media global)                : %.8g", f$q[["I"]]))
  emitir(sprintf("Erro padrao dos efeitos (s_q)    : %.6g", f$se_q))
  emitir(sprintf("t(0,975; %d)                     : %.6f", f$gl_err, f$tc))
  tabela(data.frame(
    efeito = names(f$q)[-1],
    q      = signif(as.numeric(f$q[-1]), 6),
    ic_inf = signif(as.numeric(ic_inf), 6),
    ic_sup = signif(as.numeric(ic_sup), 6),
    signif = ifelse(signif_ef, "sim", "nao")
  ))
  emitir(sprintf("Modelo: y = %.6g %+.6g*xA %+.6g*xB %+.6g*xA*xB + e",
                 f$q[["I"]], f$q[["A"]], f$q[["B"]], f$q[["AB"]]))
  emitir("q0 confere com a media das quatro medias de celula: ",
         sprintf("  q0 = %.10g, media das celulas = %.10g",
                 f$q[["I"]], mean(f$medias$y)))
  stopifnot(abs(f$q[["I"]] - mean(f$medias$y)) < 1e-12 * abs(f$q[["I"]]))

  subtitulo(sprintf("%d.3 Alocacao de variacao", num))
  tabela(data.frame(
    fonte = c("A (alocacao)", sprintf("B (%s)", f$rot_b), "AB (interacao)", "Erro"),
    SS    = signif(c(as.numeric(f$ss), f$ss_err), 6),
    pct   = round(as.numeric(f$pct), 4)
  ))
  emitir(sprintf("Soma dos percentuais             : %.6f", sum(f$pct)))
  emitir(sprintf("SS_total                         : %.6g", f$ss_tot))

  subtitulo(sprintf("%d.4 Tabela ANOVA", num))
  tabela(data.frame(
    fonte = c("A (alocacao)", sprintf("B (%s)", f$rot_b), "AB (interacao)", "Residuos"),
    gl    = f$anova[, "Df"],
    SS    = signif(f$anova[, "Sum Sq"], 6),
    MS    = signif(f$anova[, "Mean Sq"], 6),
    F     = c(signif(f$anova[1:3, "F value"], 6), NA),
    p     = c(signif(f$anova[1:3, "Pr(>F)"], 4), NA)
  ))
  emitir(sprintf("Escrituracao de gl: 1 + 1 + 1 + %d = %d = N - 1",
                 f$gl_err, sum(f$anova[, "Df"])))
  emitir("",
    "As tres provas de consistencia passaram: as somas de quadrados da matriz",
    "de sinais coincidem com as de aov(), as somas sao aditivas e portanto os",
    "percentuais fecham em 100, e a rota independente pelas medias marginais",
    "reproduz SS_A e SS_B. Tres rotas concordando e prova. Uma rota seria",
    "apenas afirmacao.")
  invisible(list(ic_inf = ic_inf, ic_sup = ic_sup, signif = signif_ef))
}

f1 <- fatorial2x2(sub1, "taxa_l1d_miss",    "B_fat1", "interchange")
f2 <- fatorial2x2(sub2, "taxa_branch_miss", "B_fat2", "unrolling")

i1 <- relatar_fatorial(f1, 6, "1", "fracao de miss de L1d")
i2 <- relatar_fatorial(f2, 7, "2", "fracao de miss de branch")

# =============================================================================
# 8. Pressupostos
# =============================================================================
titulo("8. VERIFICACAO DOS PRESSUPOSTOS")

diagnosticar <- function(f, nome) {
  e   <- residuals(f$mod)
  aj  <- fitted(f$mod)
  ord <- f$dados$ordem_execucao
  eo  <- e[order(ord)]

  sw  <- shapiro.test(e)
  cel <- interaction(f$A, f$B)
  bt  <- bartlett.test(f$y, cel)
  fl  <- fligner.test(f$y, cel)
  vars <- tapply(f$y, cel, var)
  medias_cel <- tapply(f$y, cel, mean)
  sds_cel <- sqrt(vars)
  razao_var <- max(vars) / min(vars)
  cor_ms <- cor(medias_cel, sds_cel)
  ac1 <- cor(eo[-length(eo)], eo[-1])
  lb  <- Box.test(eo, lag = 5, type = "Ljung-Box")
  dw  <- sum(diff(eo)^2) / sum(eo^2)

  subtitulo(sprintf("8.%s Fatorial %s (%s)", nome, nome, f$resp))
  emitir(sprintf("Normalidade  Shapiro-Wilk W      : %.6f   p = %.4g", sw$statistic, sw$p.value))
  emitir(sprintf("Homoced.     Bartlett K2         : %.4f    p = %.4g", bt$statistic, bt$p.value))
  emitir(sprintf("Homoced.     Fligner-Killeen     : %.4f    p = %.4g", fl$statistic, fl$p.value))
  emitir(sprintf("Homoced.     razao max/min var   : %.4g", razao_var))
  emitir(sprintf("Homoced.     cor(media, sd)      : %.4f", cor_ms))
  emitir(sprintf("Independ.    autocorr. defas. 1  : %.4f", ac1))
  emitir(sprintf("Independ.    Ljung-Box lag 5     : %.4f    p = %.4g", lb$statistic, lb$p.value))
  emitir(sprintf("Independ.    Durbin-Watson       : %.4f  (2 = sem autocorrelacao)", dw))

  # alinhamento entre as colunas de sinal e a ordem de execucao. E o teste que
  # decide se a deriva enviesa os efeitos ou apenas infla o termo de erro.
  sinais <- list(A = f$A, B = f$B, AB = f$A * f$B)
  al <- do.call(rbind, lapply(names(sinais), function(nm) {
    ct <- cor.test(sinais[[nm]], ord)
    data.frame(coluna = nm, r = round(ct$estimate, 4),
               p = signif(ct$p.value, 4),
               alinhado = ifelse(ct$p.value < 0.05, "SIM", "nao"))
  }))
  rownames(al) <- NULL
  emitir("", "Alinhamento entre coluna de sinal e ordem de execucao:")
  tabela(al)
  if (all(al$alinhado == "nao")) {
    emitir("Nenhuma coluna de sinal esta alinhada com a ordem de execucao.",
           "Portanto a deriva temporal entra no TERMO DE ERRO e nao enviesa as",
           "estimativas de efeito: ela infla o MSE, o que torna os testes F",
           "conservadores e nao otimistas.")
  } else {
    emitir("ATENCAO: ha coluna de sinal alinhada com a ordem de execucao.",
           "Nesse caso a deriva pode enviesar o efeito correspondente e a",
           "estimativa precisa ser lida com ressalva.")
  }

  list(sw = sw, bt = bt, fl = fl, razao_var = razao_var, cor_ms = cor_ms,
       ac1 = ac1, lb = lb, dw = dw, alinhamento = al,
       medias_cel = medias_cel, sds_cel = sds_cel)
}

d1 <- diagnosticar(f1, "1")
d2 <- diagnosticar(f2, "2")

emitir("",
  "Leitura honesta. Com dez replicas por celula num notebook com governor",
  "powersave e faixa de 0,4 a 5,4 GHz, a expectativa e que homocedasticidade",
  "e normalidade falhem. Normalidade falha nos contadores pelo motivo oposto",
  "ao usual: eles sao quase deterministicos, os residuos ficam quase discretos",
  "e o Shapiro-Wilk sinaliza isso com forca. Com desenho balanceado as",
  "ESTIMATIVAS de efeito sao nao viesadas qualquer que seja a distribuicao do",
  "erro. A normalidade afeta apenas a distribuicao de referencia, e a secao 10",
  "a substitui por permutacao, sem pressuposto nenhum.")

# =============================================================================
# 9. Reanalise em escala logit
# =============================================================================
titulo("9. REANALISE EM ESCALA LOGIT")

emitir("As duas respostas sao proporcoes em (0,1), portanto o estabilizador de",
       "variancia natural e o logit, log(p/(1-p)), e nao o log. A tabela abaixo",
       "poe as duas escalas lado a lado, e o texto do relatorio declara qual",
       "escala esta citando.")

sub1$logit_y <- qlogis(sub1$taxa_l1d_miss)
sub2$logit_y <- qlogis(sub2$taxa_branch_miss)
f1l <- fatorial2x2(sub1, "logit_y", "B_fat1", "interchange")
f2l <- fatorial2x2(sub2, "logit_y", "B_fat2", "unrolling")

comparar_escalas <- function(fa, fb, nome) {
  subtitulo(sprintf("9.%s Fatorial %s: influencia percentual, bruta contra logit", nome, nome))
  tabela(data.frame(
    fonte     = c("A (alocacao)", sprintf("B (%s)", fa$rot_b), "AB (interacao)", "Erro"),
    pct_bruta = round(as.numeric(fa$pct), 4),
    pct_logit = round(as.numeric(fb$pct), 4)
  ))
  emitir(sprintf("Shapiro-Wilk dos residuos: bruta p = %.4g, logit p = %.4g",
                 shapiro.test(residuals(fa$mod))$p.value,
                 shapiro.test(residuals(fb$mod))$p.value))
  cel_a <- interaction(fa$A, fa$B); cel_b <- interaction(fb$A, fb$B)
  emitir(sprintf("Fligner-Killeen          : bruta p = %.4g, logit p = %.4g",
                 fligner.test(fa$y, cel_a)$p.value,
                 fligner.test(fb$y, cel_b)$p.value))
  ord_ef_a <- names(sort(fa$pct[1:3], decreasing = TRUE))
  ord_ef_b <- names(sort(fb$pct[1:3], decreasing = TRUE))
  emitir(sprintf("Ranking dos efeitos bruta: %s", paste(ord_ef_a, collapse = " > ")))
  emitir(sprintf("Ranking dos efeitos logit: %s", paste(ord_ef_b, collapse = " > ")))
  if (identical(ord_ef_a, ord_ef_b)) {
    emitir("O ranking dos efeitos NAO muda entre as escalas.")
  } else {
    emitir("ATENCAO: o ranking dos efeitos MUDA entre as escalas, e o relatorio",
           "precisa dizer explicitamente qual escala esta citando.")
  }
}
comparar_escalas(f1, f1l, "1")
comparar_escalas(f2, f2l, "2")

# =============================================================================
# 10. Teste de permutacao de Freedman-Lane
# =============================================================================
titulo("10. TESTE DE PERMUTACAO RESTRITA (FREEDMAN-LANE)")

emitir("Permuta os residuos do modelo REDUZIDO, ou seja do modelo sem o efeito",
       "sob teste mas com todos os outros. Permutar a resposta crua estaria",
       "errado: a hipotese nula absorveria a variancia dos outros efeitos.",
       "Remove a dependencia de normalidade do veredito de significancia.")

set.seed(20260909)
n_perm <- 10000

permutar <- function(f) {
  y <- f$y
  sinais <- list(A = f$A, B = f$B, AB = f$A * f$B)
  n_obs <- length(y)
  coef_obs <- lapply(sinais, function(x) sum(x * y) / n_obs)
  media_global <- mean(y)

  sapply(names(sinais), function(nm) {
    x <- sinais[[nm]]
    ajuste_reduzido <- rep(media_global, n_obs)
    for (outro in setdiff(names(sinais), nm)) {
      ajuste_reduzido <- ajuste_reduzido + coef_obs[[outro]] * sinais[[outro]]
    }
    residuo_reduzido <- y - ajuste_reduzido
    nulos <- replicate(n_perm, abs(sum(x * sample(residuo_reduzido)) / n_obs))
    (1 + sum(nulos >= abs(coef_obs[[nm]]))) / (n_perm + 1)
  })
}

relatar_perm <- function(f, info, nome) {
  p_perm <- permutar(f)
  subtitulo(sprintf("10.%s Fatorial %s (%s)", nome, nome, f$resp))
  cmp <- data.frame(
    efeito     = names(p_perm),
    p_anova    = signif(f$anova[1:3, "Pr(>F)"], 4),
    p_perm     = signif(as.numeric(p_perm), 4),
    signif_ic  = ifelse(info$signif, "sim", "nao"),
    signif_prm = ifelse(p_perm < 0.05, "sim", "nao")
  )
  rownames(cmp) <- NULL
  tabela(cmp)
  concord <- sum((cmp$signif_ic == "sim") == (cmp$signif_prm == "sim"))
  emitir(sprintf("Concordancia entre IC e permutacao: %d de %d efeitos",
                 concord, nrow(cmp)))
  emitir(sprintf("Maior p de permutacao            : %s", fmt(max(p_perm), 4)))
  list(p = p_perm, concord = concord)
}
p1 <- relatar_perm(f1, i1, "1")
p2 <- relatar_perm(f2, i2, "2")

# =============================================================================
# 11. Resposta de tempo
# =============================================================================
titulo("11. RESPOSTA DE TEMPO DE EXECUCAO")

dados$log_tempo <- log10(dados$tempo_ms)

subtitulo("11.1 Comparacao entre os oito experimentos")
mod_caso <- aov(log_tempo ~ factor(caso), data = dados)
tabela(as.data.frame(signif(summary(mod_caso)[[1]], 6)))
emitir("Modelo em log10 do tempo porque a variabilidade do tempo cresce com a",
       "media, ver a figura media_vs_sd.pdf.")

subtitulo("11.2 Comparacoes par a par de Tukey (family-wise 95%)")
tk <- TukeyHSD(mod_caso)[[1]]
tk_df <- data.frame(par = rownames(tk), dif_log10 = signif(tk[, "diff"], 5),
                    p_ajust = signif(tk[, "p adj"], 4),
                    signif = ifelse(tk[, "p adj"] < 0.05, "sim", "nao"))
rownames(tk_df) <- NULL
tabela(tk_df)
emitir("Tukey e o que legitima qualquer afirmacao de que uma tecnica ganha de",
       "outra lida no grafico de barras: ele corrige para as 28 comparacoes.")

subtitulo("11.3 Modelo fatorial completo 4x2 (suplemento)")
mod_cheio <- aov(log_tempo ~ fTec * fAloc, data = dados)
tab_cheio <- summary(mod_cheio)[[1]]
tabela(as.data.frame(signif(tab_cheio, 6)))
ss_c <- tab_cheio[, "Sum Sq"]
pct_c <- 100 * ss_c / sum(ss_c)
tabela(data.frame(fonte = trimws(rownames(tab_cheio)),
                  gl = tab_cheio[, "Df"],
                  SS = signif(ss_c, 6),
                  pct = round(pct_c, 4)))
emitir(sprintf("Soma dos percentuais: %.6f", sum(pct_c)))
emitir("Este modelo 4x2 esta alem dos dois 2x2 pedidos pela atividade e entra",
       "como suplemento, porque usa os quatro niveis de Tecnica ao mesmo tempo.")

subtitulo("11.4 Ganho de cada tecnica sobre a base, por alocacao")
med_t <- tapply(dados$tempo_ms, list(dados$tecnica, dados$alocacao), mean)
ganho <- data.frame(
  tecnica  = rownames(med_t),
  estatica = signif(med_t[, "estatica"], 6),
  dinamica = signif(med_t[, "dinamica"], 6),
  ganho_est = signif(med_t["base", "estatica"] / med_t[, "estatica"], 4),
  ganho_din = signif(med_t["base", "dinamica"] / med_t[, "dinamica"], 4)
)
rownames(ganho) <- NULL
tabela(ganho)
razao_aloc <- mean(dados$tempo_ms[dados$alocacao == "dinamica"]) /
              mean(dados$tempo_ms[dados$alocacao == "estatica"])
emitir(sprintf("Razao media dinamica/estatica: %.4f", razao_aloc))

# =============================================================================
# 12. Figuras
# =============================================================================
titulo("12. FIGURAS")

fig <- function(nome, largura = 7.2, altura = 4.6) {
  cairo_pdf(file.path(dir_figuras, nome), width = largura, height = altura)
}

# Escala automatica: fixar 1e9 para os quatro contadores achataria
# branch_misses, que e da ordem de 1e6, contra branch_instructions, que e da
# ordem de 1e9.
escolher_escala <- function(v) {
  m <- max(v)
  if (m >= 1e9) list(f = 1e9, suf = " (10^9)")
  else if (m >= 1e6) list(f = 1e6, suf = " (10^6)")
  else if (m >= 1e3) list(f = 1e3, suf = " (10^3)")
  else list(f = 1, suf = "")
}

barras_ic <- function(s, ylab, titulo_txt, cor = claro, escala = NULL) {
  if (is.null(escala)) {
    e <- escolher_escala(s$ic_sup); escala <- e$f; ylab <- paste0(ylab, e$suf)
  }
  media <- s$media / escala; inf <- s$ic_inf / escala; sup <- s$ic_sup / escala
  rot <- sprintf("c%d\n%s\n%s", s$caso, substr(s$tecnica, 1, 6),
                 substr(s$alocacao, 1, 3))
  mp <- barplot(media, names.arg = rot, ylim = c(0, max(sup) * 1.14),
                col = cor, border = azul, las = 1, cex.names = 0.72,
                ylab = ylab, main = titulo_txt, cex.main = 0.95)

  # Intervalo mais estreito que a espessura da linha nao pode ser desenhado
  # como seta. Isso acontece de verdade nos contadores quase deterministicos,
  # e e informacao, nao defeito: o IC e invisivel na escala do grafico.
  eps <- diff(par("usr")[3:4]) * 0.004
  vis <- (sup - inf) > eps
  if (any(vis)) {
    arrows(mp[vis], inf[vis], mp[vis], sup[vis], angle = 90, code = 3,
           length = 0.04, lwd = 1.6, col = verm)
  }
  if (any(!vis)) {
    segments(mp[!vis] - 0.28, media[!vis], mp[!vis] + 0.28, media[!vis],
             lwd = 1.6, col = verm)
  }

  nota <- sprintf("n = %d, t(%d) = %.3f", r, r - 1, t_celula)
  if (any(!vis)) nota <- sprintf("%s, %d IC < espessura da linha", nota, sum(!vis))
  mtext(nota, side = 3, line = 0.1, cex = 0.62, col = cinza)
  invisible(mp)
}

# 12.1 obrigatoria: tempo com IC 95%
fig("tempo_barras.pdf")
barras_ic(desc$tempo_ms, "Tempo do kernel (ms)",
          "Tempo medio por experimento, IC de 95%", escala = 1)
invisible(dev.off())

# 12.2 boxplot do tempo, dispersao e outliers reais
fig("boxplot_tempo.pdf")
par(mar = c(6.5, 4.5, 3, 1))
bp_rot <- sprintf("c%d %s/%s", sort(unique(dados$caso)),
                  substr(desc$tempo_ms$tecnica, 1, 6),
                  substr(desc$tempo_ms$alocacao, 1, 3))
boxplot(tempo_ms ~ caso, data = dados, names = bp_rot, las = 2,
        col = claro, border = azul, outcol = verm, outpch = 19, outcex = 0.7,
        ylab = "Tempo do kernel (ms)", xlab = "",
        main = "Dispersao do tempo por experimento", cex.axis = 0.72)
mtext("Pontos em vermelho sao outliers pelo criterio de 1,5 IQR",
      side = 3, line = 0.1, cex = 0.68, col = cinza)
invisible(dev.off())

# 12.3 os quatro contadores
fig("contadores_barras.pdf", 8.4, 7.0)
par(mfrow = c(2, 2), mar = c(4.6, 4.6, 3, 1))
for (nm in c("l1d_loads", "l1d_load_misses", "branch_instructions", "branch_misses")) {
  barras_ic(desc[[nm]], "Contagem", respostas[[nm]]$rot)
}
invisible(dev.off())

# 12.4 as duas taxas
fig("taxas_barras.pdf", 8.4, 4.2)
par(mfrow = c(1, 2), mar = c(4.6, 4.8, 3, 1))
barras_ic(desc$taxa_l1d_miss, "Fracao", "Taxa de miss de L1d", escala = 1)
barras_ic(desc$taxa_branch_miss, "Fracao", "Taxa de miss de branch", escala = 1)
invisible(dev.off())

# 12.5 interacao, um por fatorial, com bigodes de IC
plot_interacao <- function(f, s_desc, casos, ylab, titulo_txt) {
  m <- f$medias
  sd_cel <- tapply(f$y, interaction(f$A, f$B), sd)
  n_cel  <- tapply(f$y, interaction(f$A, f$B), length)
  meia   <- qt(0.975, n_cel - 1) * sd_cel / sqrt(n_cel)
  chave  <- paste(m$A, m$B, sep = ".")
  m$meia <- as.numeric(meia[chave])

  xs <- c(-1, 1)
  ylim <- range(c(m$y - m$meia, m$y + m$meia))
  ylim <- ylim + c(-1, 1) * diff(ylim) * 0.18
  plot(NA, xlim = c(-1.45, 1.45), ylim = ylim, xaxt = "n",
       xlab = "Alocacao", ylab = ylab, main = titulo_txt, cex.main = 0.95)
  axis(1, at = xs, labels = c("estatica", "dinamica"))
  cores <- c(azul, verm)
  n_invis <- 0
  for (idx in seq_along(c(-1, 1))) {
    b <- c(-1, 1)[idx]
    sub <- m[m$B == b, ]
    sub <- sub[order(sub$A), ]
    lines(sub$A, sub$y, col = cores[idx], lwd = 2, type = "b", pch = 19)
    # IC mais estreito que a espessura da linha nao pode virar seta. Acontece
    # de verdade aqui, porque os contadores sao quase deterministicos, e isso
    # e informacao e nao defeito.
    eps <- diff(par("usr")[3:4]) * 0.004
    vis <- (2 * sub$meia) > eps
    if (any(vis)) {
      arrows(sub$A[vis], sub$y[vis] - sub$meia[vis],
             sub$A[vis], sub$y[vis] + sub$meia[vis],
             angle = 90, code = 3, length = 0.035, col = cores[idx], lwd = 1.3)
    }
    n_invis <- n_invis + sum(!vis)
  }
  legend("topleft", legend = c("base", f$rot_b), col = cores, lwd = 2,
         pch = 19, bty = "n", cex = 0.82)
  nota <- "Retas nao paralelas indicam interacao"
  if (n_invis > 0) {
    nota <- sprintf("%s. %d IC < espessura da linha", nota, n_invis)
  }
  mtext(nota, side = 3, line = 0.1, cex = 0.62, col = cinza)
}
fig("interacao_fat1.pdf", 5.6, 4.4)
plot_interacao(f1, desc$taxa_l1d_miss, c(1,2,3,4), "Taxa de miss de L1d",
               "Fatorial 1: alocacao x interchange")
invisible(dev.off())
fig("interacao_fat2.pdf", 5.6, 4.4)
plot_interacao(f2, desc$taxa_branch_miss, c(1,2,5,6), "Taxa de miss de branch",
               "Fatorial 2: alocacao x unrolling")
invisible(dev.off())

# 12.6 residuos, quatro paineis por fatorial
paineis_residuo <- function(f, titulo_txt) {
  e <- residuals(f$mod); aj <- fitted(f$mod)
  ord <- f$dados$ordem_execucao
  par(mfrow = c(2, 2), mar = c(4.4, 4.4, 2.8, 1))

  plot(aj, e, pch = 19, col = azul, cex = 0.7,
       xlab = "Valor ajustado", ylab = "Residuo",
       main = "Residuo contra ajustado", cex.main = 0.92)
  abline(h = 0, col = cinza, lty = 2)

  qqnorm(e, pch = 19, col = azul, cex = 0.7, main = "QQ normal", cex.main = 0.92)
  qqline(e, col = verm, lwd = 1.6)

  ep <- e / sd(e)
  plot(aj, sqrt(abs(ep)), pch = 19, col = azul, cex = 0.7,
       xlab = "Valor ajustado", ylab = expression(sqrt(abs("residuo padronizado"))),
       main = "Escala-locacao (homocedasticidade)", cex.main = 0.92)
  lines(lowess(aj, sqrt(abs(ep))), col = verm, lwd = 1.6)

  plot(ord, ep, pch = 19, col = azul, cex = 0.7,
       xlab = "Ordem de execucao", ylab = "Residuo padronizado",
       main = "Residuo contra ordem (independencia)", cex.main = 0.92)
  abline(h = 0, col = cinza, lty = 2)
  lines(lowess(ord, ep), col = verm, lwd = 1.6)
  mtext(titulo_txt, side = 3, line = -1.4, outer = TRUE, cex = 0.85, col = azul)
}
fig("residuos_fat1.pdf", 8.4, 7.0); paineis_residuo(f1, "Fatorial 1: taxa de miss de L1d"); invisible(dev.off())
fig("residuos_fat2.pdf", 8.4, 7.0); paineis_residuo(f2, "Fatorial 2: taxa de miss de branch"); invisible(dev.off())

# 12.7 media contra sd, justifica a transformacao
fig("media_vs_sd.pdf", 6.4, 4.6)
s <- desc$tempo_ms
inc <- coef(lm(log10(s$sd) ~ log10(s$media)))[2]
plot(s$media, s$sd, log = "xy", pch = 19, col = azul, cex = 1.1,
     xlab = "Media do tempo por celula (ms)", ylab = "Desvio padrao (ms)",
     main = "Relacao media-dispersao do tempo")
abline(coef(lm(log10(s$sd) ~ log10(s$media))), col = verm, lwd = 1.6)
text(s$media, s$sd, labels = sprintf("c%d", s$caso), pos = 4, cex = 0.68, col = cinza)
legend("topleft", legend = sprintf("inclinacao = %.3f", inc), bty = "n", cex = 0.85)
mtext("Inclinacao perto de 1 indica log, perto de 0,5 raiz, perto de 0 nenhuma",
      side = 3, line = 0.1, cex = 0.66, col = cinza)
invisible(dev.off())

# 12.8 Pareto de influencia
fig("pareto_influencia.pdf", 8.4, 4.0)
par(mfrow = c(1, 2), mar = c(4.4, 8.2, 3, 1))
for (f in list(f1, f2)) {
  v <- as.numeric(f$pct)
  nomes <- c("A alocacao", sprintf("B %s", f$rot_b), "AB interacao", "Erro")
  o <- order(v)
  mp <- barplot(v[o], names.arg = nomes[o], horiz = TRUE, las = 1, col = claro,
                border = azul, xlim = c(0, max(v) * 1.22), cex.names = 0.78,
                xlab = "Influencia (% de SS_total)",
                main = sprintf("%s", f$resp), cex.main = 0.9)
  text(v[o], mp, labels = sprintf("%.2f%%", v[o]),
       pos = 4, cex = 0.72, col = azul, xpd = NA)
}
invisible(dev.off())

# 12.9 ordem de execucao, tempo
fig("ordem_execucao.pdf", 7.2, 4.2)
e_t <- residuals(mod_caso) / sd(residuals(mod_caso))
plot(dados$ordem_execucao, e_t, pch = 19, col = azul, cex = 0.75,
     xlab = "Ordem de execucao", ylab = "Residuo padronizado (log10 do tempo)",
     main = "Deriva temporal ao longo da coleta")
abline(h = 0, col = cinza, lty = 2)
lines(lowess(dados$ordem_execucao, e_t), col = verm, lwd = 2)
ac1_t <- cor(e_t[order(dados$ordem_execucao)][-nrow(dados)],
             e_t[order(dados$ordem_execucao)][-1])
legend("topright", legend = sprintf("autocorr. defas. 1 = %.3f", ac1_t),
       bty = "n", cex = 0.82)
invisible(dev.off())

figs <- list.files(dir_figuras, pattern = "[.]pdf$")
emitir(sprintf("Figuras geradas (%d):", length(figs)))
emitir(paste0("  ", figs))

# =============================================================================
# 13. Tabelas e macros para o relatorio
# =============================================================================
titulo("13. TABELAS E MACROS PARA O RELATORIO")

linhas_desc <- sapply(seq_len(nrow(desc$tempo_ms)), function(i) {
  s <- desc$tempo_ms[i, ]
  sl <- desc$taxa_l1d_miss[i, ]; sb <- desc$taxa_branch_miss[i, ]
  sprintf("%d & %s & %s & %s & %s & %s & %s & %s \\\\",
          s$caso, s$tecnica, s$alocacao,
          fmtm(s$media, 1), fmtm(s$cv, 2),
          fmtm(100 * sl$media, 3), fmtm(100 * sb$media, 4),
          fmtm(s$sd, 1))
})
escrever_tabela(linhas_desc, "tabela_experimentos.tex")

tab_fat <- function(f, arquivo) {
  nomes <- c("$A$ (aloca\\c{c}\\~ao)",
             sprintf("$B$ (%s)", f$rot_b),
             "$AB$ (intera\\c{c}\\~ao)", "Erro")
  # SS em notacao cientifica e influencia com 4 casas: no Fatorial 2 os efeitos
  # sao da ordem de 1e-12 e arredondar para 2 casas os imprimiria como zero.
  linhas <- c(
    sapply(1:3, function(i) sprintf("%s & %s & %s & %s & %s \\\\",
      nomes[i], fmtsci(as.numeric(f$ss)[i]), fmtm(as.numeric(f$pct)[i], 4),
      fmtsci(as.numeric(f$q[-1])[i]), fmt_p(f$anova[i, "Pr(>F)"]))),
    sprintf("%s & %s & %s & -- & -- \\\\", nomes[4],
            fmtsci(f$ss_err), fmtm(as.numeric(f$pct)[4], 4)))
  escrever_tabela(linhas, arquivo)
}
tab_fat(f1, "tabela_fatorial1.tex")
tab_fat(f2, "tabela_fatorial2.tex")

# ---------------------------------------------------------------------------
# Tabela: tempo de resposta com IC 95% (Analise 1 do enunciado)
# ---------------------------------------------------------------------------
st <- desc$tempo_ms
escrever_tabela(sapply(seq_len(nrow(st)), function(i) {
  sprintf("%d & %s & %s & %s & %s & %s & %s & %s \\\\",
          st$caso[i], st$tecnica[i], st$alocacao[i],
          fmtm(st$media[i], 1), fmtm(st$meia[i], 1),
          fmtm(st$ic_inf[i], 1), fmtm(st$ic_sup[i], 1), fmtm(st$cv[i], 2))
}), "tabela_tempo.tex")

# ---------------------------------------------------------------------------
# Tabela: os quatro contadores com IC 95%, exigidos pelo enunciado
# ---------------------------------------------------------------------------
escrever_tabela(sapply(seq_len(nrow(st)), function(i) {
  sprintf("%d & %s & %s & %s & %s & %s & %s \\\\",
          st$caso[i], substr(st$tecnica[i], 1, 11), substr(st$alocacao[i], 1, 8),
          sprintf("%s $\\pm$ %s", fmtm(desc$l1d_loads$media[i] / 1e9, 3),
                                   fmtm(desc$l1d_loads$meia[i] / 1e9, 4)),
          sprintf("%s $\\pm$ %s", fmtm(desc$l1d_load_misses$media[i] / 1e6, 2),
                                   fmtm(desc$l1d_load_misses$meia[i] / 1e6, 2)),
          sprintf("%s $\\pm$ %s", fmtm(desc$branch_instructions$media[i] / 1e9, 3),
                                   fmtm(desc$branch_instructions$meia[i] / 1e9, 4)),
          sprintf("%s $\\pm$ %s", fmtm(desc$branch_misses$media[i] / 1e6, 3),
                                   fmtm(desc$branch_misses$meia[i] / 1e6, 3)))
}), "tabela_contadores.tex")

# ---------------------------------------------------------------------------
# Tabelas: ANOVA de cada fatorial, e o modelo completo 4x2
# ---------------------------------------------------------------------------
tab_anova <- function(f, arquivo) {
  nomes <- c("$A$ (aloca\\c{c}\\~ao)", sprintf("$B$ (%s)", f$rot_b),
             "$AB$ (intera\\c{c}\\~ao)", "Res\\'iduos")
  linhas <- c(
    sapply(1:3, function(i) sprintf("%s & %d & %s & %s & %s & %s \\\\",
      nomes[i], f$anova[i, "Df"], fmtsci(f$anova[i, "Sum Sq"]),
      fmtsci(f$anova[i, "Mean Sq"]), fmtsci(f$anova[i, "F value"]),
      fmt_p(f$anova[i, "Pr(>F)"]))),
    sprintf("%s & %d & %s & %s & -- & -- \\\\", nomes[4],
            f$anova[4, "Df"], fmtsci(f$anova[4, "Sum Sq"]),
            fmtsci(f$anova[4, "Mean Sq"])))
  escrever_tabela(linhas, arquivo)
}
tab_anova(f1, "tabela_anova_fatorial1.tex")
tab_anova(f2, "tabela_anova_fatorial2.tex")

nomes_c <- c("T\\'ecnica", "Aloca\\c{c}\\~ao",
             "T\\'ecnica $\\times$ Aloca\\c{c}\\~ao", "Res\\'iduos")
escrever_tabela(sapply(seq_len(nrow(tab_cheio)), function(i) {
  sprintf("%s & %d & %s & %s & %s & %s & %s \\\\",
          nomes_c[i], tab_cheio[i, "Df"], fmtm(tab_cheio[i, "Sum Sq"], 5),
          fmtm(pct_c[i], 2), fmtm(tab_cheio[i, "Mean Sq"], 6),
          ifelse(i < 4, fmtm(tab_cheio[i, "F value"], 2), "--"),
          ifelse(i < 4, fmt_p(tab_cheio[i, "Pr(>F)"]), "--"))
}), "tabela_modelo_completo.tex")

# ---------------------------------------------------------------------------
# Tabela: pressupostos dos dois fatoriais lado a lado
# ---------------------------------------------------------------------------
linhas_pre <- c(
  sprintf("Shapiro-Wilk, $p$ & %s & %s \\\\", fmtsci(d1$sw$p.value), fmtsci(d2$sw$p.value)),
  sprintf("Bartlett, $p$ & %s & %s \\\\", fmtsci(d1$bt$p.value), fmtsci(d2$bt$p.value)),
  sprintf("Fligner-Killeen, $p$ & %s & %s \\\\", fmtsci(d1$fl$p.value), fmtsci(d2$fl$p.value)),
  sprintf("Raz\\~ao m\\'axima entre vari\\^ancias & %s & %s \\\\", fmtm(d1$razao_var, 1), fmtm(d2$razao_var, 1)),
  sprintf("Autocorrela\\c{c}\\~ao de defasagem 1 & %s & %s \\\\", fmtm(d1$ac1, 3), fmtm(d2$ac1, 3)),
  sprintf("Durbin-Watson & %s & %s \\\\", fmtm(d1$dw, 3), fmtm(d2$dw, 3)),
  sprintf("Ljung-Box (5 defasagens), $p$ & %s & %s \\\\", fmtm(d1$lb$p.value, 3), fmtm(d2$lb$p.value, 3)),
  sprintf("Maior $|r|$ entre sinal e ordem & %s & %s \\\\", fmtm(max(abs(d1$alinhamento$r)), 3), fmtm(max(abs(d2$alinhamento$r)), 3)))
escrever_tabela(linhas_pre, "tabela_pressupostos.tex")

# ---------------------------------------------------------------------------
# Tabela: permutacao de Freedman-Lane contra ANOVA
# ---------------------------------------------------------------------------
linhas_perm <- unlist(lapply(list(list(f1, p1, i1, "1"), list(f2, p2, i2, "2")),
  function(z) {
    f <- z[[1]]; pp <- z[[2]]; ii <- z[[3]]; nm <- z[[4]]
    sapply(1:3, function(i) sprintf("%s & %s & %s & %s & %s & %s \\\\",
      nm, names(pp$p)[i], fmt_p(f$anova[i, "Pr(>F)"]), fmt_p(pp$p[i]),
      ifelse(ii$signif[i], "sim", "n\\~ao"),
      ifelse(pp$p[i] < 0.05, "sim", "n\\~ao")))
  }))
escrever_tabela(linhas_perm, "tabela_permutacao.tex")

# ---------------------------------------------------------------------------
# Tabela: influencia percentual, escala bruta contra logit
# ---------------------------------------------------------------------------
linhas_log <- unlist(lapply(list(list(f1, f1l, "1"), list(f2, f2l, "2")),
  function(z) {
    fa <- z[[1]]; fb <- z[[2]]; nm <- z[[3]]
    rot <- c("$A$", sprintf("$B$ (%s)", fa$rot_b), "$AB$", "Erro")
    sapply(1:4, function(i) sprintf("%s & %s & %s & %s \\\\",
      nm, rot[i], fmtm(as.numeric(fa$pct)[i], 4), fmtm(as.numeric(fb$pct)[i], 4)))
  }))
escrever_tabela(linhas_log, "tabela_logit.tex")

# ---------------------------------------------------------------------------
# Tabela: validacao cruzada dos nomes de evento, lida de dados/eventos.txt
# ---------------------------------------------------------------------------
ev_txt <- readLines(file.path(dir_dados, "eventos.txt"), warn = FALSE)
razoes <- grep("^razao ", ev_txt, value = TRUE)
if (length(razoes) == 4) {
  nomes_ev <- c("\\texttt{L1-dcache-loads}", "\\texttt{L1-dcache-load-misses}",
                "\\texttt{branch-instructions}", "\\texttt{branch-misses}")
  nativos <- c("\\texttt{mem\\_inst\\_retired.all\\_loads}",
               "\\texttt{mem\\_load\\_retired.l1\\_miss}",
               "\\texttt{br\\_inst\\_retired.all\\_branches}",
               "\\texttt{br\\_misp\\_retired.all\\_branches}")
  vals <- as.numeric(sub("^.*: *", "", razoes))
  escrever_tabela(sapply(1:4, function(i)
    sprintf("%s & %s & %s \\\\", nomes_ev[i], nativos[i], fmtm(vals[i], 4))),
    "tabela_eventos.tex")
  for (i in 1:4) add_macro(paste0("valRazaoEv", c("Loads","Misses","Brinst","Brmiss")[i]), fmt(vals[i], 4))
  emitir("", sprintf("Validacao cruzada dos nomes de evento (razao alias/nativo): %s",
                     paste(fmt(vals, 4), collapse = ", ")))
} else {
  emitir("", "AVISO: validacao cruzada de eventos ausente em dados/eventos.txt")
}

# ---------------------------------------------------------------------------
# Macros adicionais, com precisao suficiente para os efeitos minusculos
# ---------------------------------------------------------------------------
add_macro("valFatUmPctErroP", fmt(as.numeric(f1$pct)[4], 4))
add_macro("valFatDoisPctAP",  fmt(as.numeric(f2$pct)[1], 4))
add_macro("valFatDoisPctBP",  fmt(as.numeric(f2$pct)[2], 4))
add_macro("valFatDoisPctABP", fmt(as.numeric(f2$pct)[3], 4))
add_macro("valFatDoisPctErroP", fmt(as.numeric(f2$pct)[4], 4))
add_macro("valFatDoisPvalA", fmt(f2$anova[1, "Pr(>F)"], 3))
add_macro("valFatDoisPvalAB", fmt(f2$anova[3, "Pr(>F)"], 4))
add_macro("valPctTec",   fmt(pct_c[1], 2))
add_macro("valPctAloc",  fmt(pct_c[2], 2))
add_macro("valPctInter", fmt(pct_c[3], 2))
add_macro("valPctResid", fmt(pct_c[4], 2))
add_macro("valDesescalonado", desescalonado)
add_macro("valTukeySignif", sum(tk[, "p adj"] < 0.05))
add_macro("valTukeyTotal", nrow(tk))
add_macro("valTPooled", fmt(qt(0.975, 8 * (r - 1)), 4))
for (tc in c("base", "interchange", "unrolling", "tiling")) {
  nm <- c(base = "Base", interchange = "Inter", unrolling = "Unroll", tiling = "Tiling")[tc]
  add_macro(paste0("valBrinst", nm),
            fmt(mean(dados$branch_instructions[dados$tecnica == tc]) / 1e9, 3))
  add_macro(paste0("valTaxaCache", nm),
            fmt(100 * mean(dados$taxa_l1d_miss[dados$tecnica == tc]), 3))
  add_macro(paste0("valTaxaBr", nm),
            fmt(100 * mean(dados$taxa_branch_miss[dados$tecnica == tc]), 4))
}
# Diferenca de loads entre as familias, por tecnica. Sai constante, o que e a
# assinatura estrutural da indirecao de ponteiro da alocacao dinamica.
delta_loads <- sapply(c("base","interchange","unrolling","tiling"), function(tc) {
  mean(dados$l1d_loads[dados$tecnica == tc & dados$alocacao == "dinamica"]) -
  mean(dados$l1d_loads[dados$tecnica == tc & dados$alocacao == "estatica"])
})
subtitulo("11.5 Diferenca de loads entre alocacoes, por tecnica")
tabela(data.frame(tecnica = names(delta_loads),
                  delta_1e9 = round(delta_loads / 1e9, 4)))
emitir(sprintf("Media: %.4f e9, amplitude: %.4f e9",
               mean(delta_loads) / 1e9, diff(range(delta_loads)) / 1e9))
emitir("Constancia dessa diferenca entre as quatro tecnicas indica que ela e",
       "estrutural, vinda da indirecao de ponteiro, e nao do padrao de acesso.")
add_macro("valDeltaLoads", fmt(mean(delta_loads) / 1e9, 3))
add_macro("valDeltaLoadsAmp", fmt(diff(range(delta_loads)) / 1e9, 4))
for (tc in c("base","interchange","unrolling","tiling")) {
  nm <- c(base="Base", interchange="Inter", unrolling="Unroll", tiling="Tiling")[tc]
  add_macro(paste0("valMissAbsEst", nm),
    fmt(mean(dados$l1d_load_misses[dados$tecnica == tc & dados$alocacao == "estatica"]) / 1e6, 1))
  add_macro(paste0("valMissAbsDin", nm),
    fmt(mean(dados$l1d_load_misses[dados$tecnica == tc & dados$alocacao == "dinamica"]) / 1e6, 1))
}
add_macro("valStrideLinha", format(1000 * 4, big.mark = ".", decimal.mark = ","))
add_macro("valPeriodoConjunto", format(64 * 64, big.mark = ".", decimal.mark = ","))
add_macro("valLinhasPorConjunto", fmt(1000 / 64, 1))
add_macro("valAssociatividade", 12)
add_macro("valBrinstPrevisto", fmt((1000^3 + 1000^2 + 1000) / 1e9, 3))
add_macro("valBrinstPrevistoUnroll", fmt((1000^3 / 4 + 1000^2 + 1000) / 1e9, 3))
add_macro("valTaxaCacheBaseEst", fmt(100 * desc$taxa_l1d_miss$media[1], 3))
add_macro("valTaxaCacheBaseDin", fmt(100 * desc$taxa_l1d_miss$media[2], 3))
add_macro("valLoadsBaseEst", fmt(desc$l1d_loads$media[1] / 1e9, 3))
add_macro("valLoadsBaseDin", fmt(desc$l1d_loads$media[2] / 1e9, 3))
add_macro("valMissesBaseEst", fmt(desc$l1d_load_misses$media[1] / 1e6, 1))
add_macro("valMissesBaseDin", fmt(desc$l1d_load_misses$media[2] / 1e6, 1))
add_macro("valFatUmShapiroP", fmt(d1$sw$p.value, 6))
add_macro("valFatDoisShapiroP", fmt(d2$sw$p.value, 4))
add_macro("valFatDoisFlignerLogitP", fmt(fligner.test(f2l$y, interaction(f2l$A, f2l$B))$p.value, 3))

add_macro("valNMatriz", format(dados$n[1], big.mark = ".", decimal.mark = ","))
cfg <- readLines(file.path(raiz, "matrix_config.h"))
ler_define <- function(nome) {
  ln <- grep(sprintf("^#define %s ", nome), cfg, value = TRUE)
  stopifnot(length(ln) == 1)
  as.integer(sub(sprintf("^#define %s +([0-9]+).*$", nome), "\\1", ln))
}
stopifnot(ler_define("N") == dados$n[1])
add_macro("valBloco", ler_define("BLOCO"))
add_macro("valUnroll", ler_define("UNROLL"))
add_macro("valReplicas", r)
add_macro("valMedicoes", n_total)
add_macro("valChecksum", format(dados$checksum[1], scientific = FALSE, big.mark = ".", decimal.mark = ","))
add_macro("valTCelula", fmt(t_celula, 4))
add_macro("valCvTempoMin", fmt(min(desc$tempo_ms$cv), 2))
add_macro("valCvTempoMax", fmt(max(desc$tempo_ms$cv), 2))
add_macro("valCvLoadsMax", fmt(max(desc$l1d_loads$cv), 4))
add_macro("valCvBrinstMax", fmt(max(desc$branch_instructions$cv), 4))
add_macro("valRazaoAloc", fmt(razao_aloc, 3))
for (i in seq_len(nrow(ganho))) {
  nm <- c(base = "Base", interchange = "Inter", unrolling = "Unroll", tiling = "Tiling")[ganho$tecnica[i]]
  add_macro(paste0("valGanhoEst", nm), fmt(ganho$ganho_est[i], 2))
  add_macro(paste0("valGanhoDin", nm), fmt(ganho$ganho_din[i], 2))
}
for (nome_f in c("Um", "Dois")) {
  f  <- if (nome_f == "Um") f1 else f2
  fl <- if (nome_f == "Um") f1l else f2l
  dd <- if (nome_f == "Um") d1 else d2
  pp <- if (nome_f == "Um") p1 else p2
  add_macro(paste0("valFat", nome_f, "PctA"),    fmt(as.numeric(f$pct)[1], 2))
  add_macro(paste0("valFat", nome_f, "PctB"),    fmt(as.numeric(f$pct)[2], 2))
  add_macro(paste0("valFat", nome_f, "PctAB"),   fmt(as.numeric(f$pct)[3], 2))
  add_macro(paste0("valFat", nome_f, "PctErro"), fmt(as.numeric(f$pct)[4], 2))
  add_macro(paste0("valFat", nome_f, "PctLogA"), fmt(as.numeric(fl$pct)[1], 2))
  add_macro(paste0("valFat", nome_f, "PctLogB"), fmt(as.numeric(fl$pct)[2], 2))
  add_macro(paste0("valFat", nome_f, "PctLogAB"),fmt(as.numeric(fl$pct)[3], 2))
  add_macro(paste0("valFat", nome_f, "GlErro"),  f$gl_err)
  add_macro(paste0("valFat", nome_f, "Ac"),      fmt(dd$ac1, 3))
  add_macro(paste0("valFat", nome_f, "Dw"),      fmt(dd$dw, 3))
  add_macro(paste0("valFat", nome_f, "RazaoVar"),fmt(dd$razao_var, 2))
  add_macro(paste0("valFat", nome_f, "PermMax"), fmt(max(pp$p), 4))
  add_macro(paste0("valFat", nome_f, "PermConc"),pp$concord)
  add_macro(paste0("valFat", nome_f, "AlinhaMax"),
            fmt(max(abs(dd$alinhamento$r)), 3))
}
writeLines(macros, file.path(dir_tex, "macros.tex"))

emitir(sprintf("Macros geradas                    : %d", length(macros)))
emitir(sprintf("Nomes duplicados                  : %d",
               sum(duplicated(sub("^\\\\newcommand\\{\\\\([^}]+)\\}.*$", "\\1", macros)))))
nomes_macro <- sub("^\\\\newcommand\\{\\\\([^}]+)\\}.*$", "\\1", macros)
com_digito <- nomes_macro[grepl("[^A-Za-z]", nomes_macro)]
emitir(sprintf("Nomes invalidos em TeX (nao-letras) : %d", length(com_digito)))
if (length(com_digito) > 0) emitir(paste0("  ", com_digito))
# Fatal: nome de macro do LaTeX aceita apenas letras. Um digito faz o TeX
# truncar o nome, redefinir outra macro e vazar o resto como texto solto.
stopifnot(length(com_digito) == 0)
stopifnot(!any(duplicated(nomes_macro)))
emitir("Arquivos em analise/tex/: macros.tex, tabela_experimentos.tex,",
       "tabela_fatorial1.tex, tabela_fatorial2.tex")

titulo("FIM")
emitir(sprintf("Resultados completos em %s", saida))
close(con)
