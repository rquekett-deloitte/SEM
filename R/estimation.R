library(tidyverse)

build_lhrs_frame <- function(data, end_date) {
  data %>%
    mutate(
      z = log(Lhrs) - log(lag(KTotal)),
      y = z - lag(z),
      lr_g = log(Ygdp) - log(lag(KTotal)),
      gap = (Ygdp - YgdpHpf) / YgdpHpf,
      rw = log(Lwge) - log(Pgdp),
      rw1 = log(lag(Lwge)) - log(lag(Pgdp)),
      ec = log(lag(Lhrs)) - log(lag(KTotal, 2))
    ) %>%
    filter(date >= as.Date("1985-06-01"), date <= as.Date(end_date))
}

# Estimate every model equation on the prepared estimation dataset.
# Returns:
#   fits   - named list of fitted model objects (lm / nls / optim)
#   frames - each equation's final estimation frame (with dates), used by the
#            forecast validation harness to check evaluators against fitted()
#   data   - the estimation data augmented with Rstar (RTS-smoothed neutral
#            rate from the Rcash state-space model)
#   bs_c2  - Balassa-Samuelson weight estimated during data preparation
estimate_model <- function(data, estimation_end = NULL) {

  # Estimate every equation to the most recent historical period by default:
  # every window below follows the data end, so an updated Data.xlsx
  # re-estimates automatically. Pass estimation_end to pin a vintage.
  end <- if (is.null(estimation_end)) max(as.Date(data$date)) else as.Date(estimation_end)

dlog <- function(x) log(x) - log(lag(x))

fits <- list()
frames <- list()

# ---- Private consumption -----------------------------------------------------
cpr <- data %>%
  mutate(
    y    = dlog(Cpr),
    l_c  = lag(log(Cpr)),
    l_yr = lag(log(Yhdi / Pgdp)),
    l_wr = lag(log(Whh / Pgdp)),
    l_r  = lag(R90dReal),
    d_w  = dlog(Whh),
    d_y  = dlog(Yhdi),
    d_y1 = lag(dlog(Yhdi)),
    d_y2 = lag(dlog(Yhdi), 2),
    d_u  = 4 * (Lur - lag(Lur))
  ) %>%
  filter(date >= "1988-12-01", date <= end)
cpr_base <- nls(
  y ~ c1 + c2 * (l_c - c3 * l_yr - (1 - c3) * l_wr + 0.5 * l_r) +
    c6 * d_w + c8 * d_y + c9 * d_y1 + c10 * d_y2 + c11 * d_u,
  data = cpr, na.action = na.exclude,
  start = list(c1 = 0, c2 = -0.1, c3 = 0.5, c6 = 0, c8 = 0, c9 = 0, c10 = 0, c11 = 0)
)
# The COVID dummy loads on the base-equation residual, so the pandemic
# quarters carry their consumption displacement into the final fit.
cpr <- cpr %>% mutate(dum = dum_covid_cpr * coalesce(as.numeric(residuals(cpr_base)), 0))
fits$Cpr <- nls(
  y ~ c1 + c2 * (l_c - c3 * l_yr - (1 - c3) * l_wr + 0.5 * l_r) +
    c6 * d_w + c8 * d_y + c9 * d_y1 + c10 * d_y2 + c11 * d_u + c12 * dum,
  data = cpr, na.action = na.exclude,
  start = list(c1 = 0, c2 = -0.1, c3 = 0.5, c6 = 0, c8 = 0, c9 = 0, c10 = 0, c11 = 0, c12 = 0)
)
frames$Cpr <- cpr

# ---- Dwelling investment -------------------------------------------------------
idwell <- data %>%
  mutate(
    y    = dlog(Idwell),
    l_i  = lag(log(Idwell)),
    l_c  = lag(log(Cpr)),
    l_p  = lag(log(Pidwell)) - lag(log(Ppcd)),
    l_r  = lag(RmortRealExgst),
    d_h1 = lag(dlog(PhouseReal)),
    d_h2 = lag(dlog(PhouseReal), 2),
    d_h3 = lag(dlog(PhouseReal), 3),
    d_h4 = lag(dlog(PhouseReal), 4)
  ) %>%
  filter(date >= "2005-03-01", date <= end)
fits$Idwell <- nls(
  y ~ c1 + c2 * (l_i - l_c - c4 * l_p - c5 * l_r) +
    c7 * d_h1 + c8 * d_h2 + c9 * d_h3 + c10 * d_h4 +
    c11 * dum_2020q2 + c13 * dum_2020q4 + c14 * dum_2021q1,
  data = idwell,
  start = list(c1 = 0, c2 = -0.1, c4 = 0.5, c5 = 0.5, c7 = 0, c8 = 0,
               c9 = 0, c10 = 0, c11 = 0, c13 = 0, c14 = 0)
)
frames$Idwell <- idwell

# ---- Mining investment ---------------------------------------------------------
imin <- data %>%
  mutate(
    y    = dlog(Imin),
    l_i  = lag(log(Imin)),
    l_g  = lag(log(Ygdp)),
    l_p  = lag(log(Pxmin / Pgdp)),      # relative mining export price (long run)
    d_p0 = dlog(Pxmin),                 # short-run terms enter unrebased
    d_p1 = lag(dlog(Pxmin)),
    d_p2 = lag(dlog(Pxmin), 2),
    d2_i = lag(log(Imin) - 2 * lag(log(Imin)) + lag(log(Imin), 2))
  ) %>%
  filter(date >= "2002-06-01", date <= end)
fits$Imin <- nls(
  y ~ c1 + c2 * (l_i - l_g - c3 * l_p) + c4 * d_p0 + c5 * d_p1 + c6 * d_p2 + c7 * d2_i,
  data = imin,
  start = list(c1 = 0, c2 = -0.1, c3 = 0.5, c4 = 0, c5 = 0, c6 = 0, c7 = 0)
)
frames$Imin <- imin

# ---- Non-farm inventories --------------------------------------------------------
ivtnf <- data %>%
  mutate(
    y    = dlog(IvtNonfarm),
    l_v  = lag(log(IvtNonfarm)),
    l_g  = lag(log(Ygdp)),
    d_v1 = lag(dlog(IvtNonfarm)),
    d_v2 = lag(dlog(IvtNonfarm), 2),
    d_g1 = lag(dlog(Ygdp))
  ) %>%
  filter(date >= "1986-03-01", date <= end)
fits$IvtNonfarm <- nls(
  y ~ c1 + c2 * (l_v - l_g + c3 * trend + c4 * trend^2 + c5 * trend^3) +
    c6 * d_v1 + c7 * d_v2 + c8 * d_g1,
  data = ivtnf,
  start = list(c1 = 0, c2 = -0.1, c3 = 0, c4 = 0, c5 = 0, c6 = 0, c7 = 0, c8 = 0)
)
frames$IvtNonfarm <- ivtnf

# ---- Corporate income tax ---------------------------------------------------------
tcit <- data %>%
  mutate(
    y   = dlog(Tcit),
    l_t = lag(log(Tcit)),
    l_g = lag(log(Ygoa)),
    l_p = lag(log(Ptot)),
    d_g = dlog(Ygoa),
    d_p = dlog(Fpcom / Pgdp)
  ) %>%
  filter(date >= "1974-12-01", date <= end)
fits$Tcit <- nls(
  y ~ c1 + c2 * (l_t - l_g - c5 * l_p) + c6 * d_g + c7 * d_p,
  data = tcit,
  start = list(c1 = 0, c2 = -0.1, c5 = 0.5, c6 = 0, c7 = 0)
)
frames$Tcit <- tcit

# ---- Payroll tax --------------------------------------------------------------------
tprl <- data %>%
  mutate(
    y  = dlog(Tprl),
    c2 = lag(log(Tprl)) - lag(log(Ywss)),
    c4 = Lur - LurHpf,
    c5 = log(lag(Lemp)) - 4 * log(lag(Lemp, 2)) + 6 * log(lag(Lemp, 3)) -
      4 * log(lag(Lemp, 4)) + log(lag(Lemp, 5))
  ) %>%
  filter(date >= "1975-12-01", date <= end)
fits$Tprl <- lm(y ~ c2 + c4 + c5, data = tprl)
frames$Tprl <- tprl

# ---- Other taxes (residual tax head) ---------------------------------------------------
toth <- data %>%
  mutate(
    y    = dlog(Toth),
    l_t  = lag(log(Toth)),
    l_g  = lag(log(YgdpNom)),
    dgst = lag(ShockGst),
    d_g  = dlog(YgdpNom)
  ) %>%
  filter(date >= "1974-12-01", date <= end)
fits$Toth <- nls(
  y ~ c1 + c2 * (l_t - l_g - c3 * dgst) + c4 * d_g,
  data = toth, na.action = na.exclude,
  start = list(c1 = -0.17, c2 = -0.07, c3 = -0.48, c4 = 0.91)
)
frames$Toth <- toth

# ---- Transfers to persons ------------------------------------------------------------
ytsf <- data %>%
  mutate(
    y   = dlog(Ytsf),
    l_t = lag(log(Ytsf)),
    l_g = lag(log(YgdpNom)),
    l_u = lag(log(Lune * Pcpi)),
    d_e = dlog(Lemp),
    gap = lag(Lur) - lag(LurHpf),
    dum = DumTsfTot
  ) %>%
  filter(date >= "1976-06-01", date <= end)
fits$Ytsf <- nls(
  y ~ c1 + c2 * (l_t - c3 * l_g - (1 - c3) * l_u) + c4 * d_e + c5 * gap + c6 * q3 + c7 * dum,
  data = ytsf, na.action = na.exclude,
  start = list(c1 = 0, c2 = -0.1, c3 = 0.5, c4 = 0, c5 = 0, c6 = 0, c7 = 0)
)
frames$Ytsf <- ytsf

# ---- Resource exports -----------------------------------------------------------------
xmin <- data %>%
  mutate(
    y   = dlog(Xmin),
    c2  = lag(log(Xmin)) - lag(log(KMin)),
    c3  = lag(dlog(Xmin)),
    c4  = lag(dlog(FcGdp)),
    c5  = lag(dlog(FcGdp), 2),
    c6  = lag(dlog(FcGdp), 3),
    c7  = lag(dlog(FcPpp)),
    c8  = lag(dlog(FcPpp), 2),
    c9  = lag(dlog(FcPpp), 3),
    c10 = lag(dlog(Fpcom)),
    c11 = lag(dlog(Fpcom), 2),
    c12 = lag(dlog(Fpcom), 3)
  ) %>%
  filter(date >= "1983-03-01", date <= end)
fits$Xmin <- lm(y ~ c2 + c3 + c4 + c5 + c6 + c7 + c8 + c9 + c10 + c11 + c12, data = xmin)
frames$Xmin <- xmin

# ---- Average hours worked (market sector) ---------------------------------------------
lavh <- data %>%
  mutate(gap = (Lur - LurHpf) / Lur, Lavh_q = LavhMkt) %>%
  filter(date >= "1984-12-01", date <= end) %>%
  mutate(l_avh = lag(Lavh_q), l_gap = lag(gap), l_t98 = lag(trend_98))
lavh_base <- nls(
  Lavh_q ~ rho * l_avh + (1 - rho) * c1 + c2 * (gap - rho * l_gap) +
    c4 * (trend_98 - rho * l_t98),
  data = lavh, na.action = na.exclude,
  start = list(rho = 0.5, c1 = mean(lavh$Lavh_q, na.rm = TRUE), c2 = 0, c4 = 0)
)
p <- coef(lavh_base)
# The COVID dummy enters as (fit - actual) rather than (actual - fit) so its
# coefficient carries a negative sign, matching the legacy sign convention.
lavh <- lavh %>%
  mutate(
    dum   = dum_covid_avh * ((p[["c1"]] + p[["c2"]] * gap + p[["c4"]] * trend_98) - Lavh_q),
    l_dum = lag(dum)
  )
fits$Lavh <- nls(
  Lavh_q ~ rho * l_avh + (1 - rho) * c1 + c2 * (gap - rho * l_gap) +
    c3 * (dum - rho * l_dum) + c4 * (trend_98 - rho * l_t98),
  data = lavh, na.action = na.exclude,
  start = list(rho = coef(lavh_base)[["rho"]], c1 = p[["c1"]],
               c2 = p[["c2"]], c3 = 0, c4 = p[["c4"]])
)
frames$Lavh <- lavh

# ---- Non-market employment --------------------------------------------------------------
lempnm <- data %>%
  mutate(
    y  = log(LempNonmkt),
    c2 = log(LempMkt),
    c3 = trend_01,
    c4 = log(GovDem)
  ) %>%
  filter(date >= "1984-12-01", date <= end)
fits$LempNonmkt <- lm(y ~ c2 + c3 + c4, data = lempnm)
frames$LempNonmkt <- lempnm

# ---- Participation rate -------------------------------------------------------------------
lpar <- data %>%
  mutate(
    y  = Lpar - lag(Lpar),
    c2 = lag(Lpar) - lag(LparHpf),
    c3 = Lur - LurHpf,
    c4 = Lur - lag(Lur),
    c5 = lag(Lur) - lag(Lur, 2),
    c6 = lag(Lwge/Pcpi) - lag(Lwge/Pcpi, 5),
    c7 = dum_2020q2,
    c8 = dum_2020q3,
    c9 = dum_2020q4
  ) %>%
  filter(date >= "1975-12-01", date <= end)
fits$Lpar <- lm(y ~ c2 + c3 + c4 + c5 + c6 + c7 + c8 + c9, data = lpar)
frames$Lpar <- lpar

# ---- Wages -----------------------------------------------------------------------------------
lwge <- data %>%
  mutate(
    dp_hpf = dlog(PpcdHpf),
    y  = dlog(Lwge) - dp_hpf,
    c2 = lag(dlog(Ppcd), 3) - dp_hpf,
    c3 = (Lur - LurHpf) / Lur,
    c4 = Lur - lag(Lur),
    c5 = lag(Lur) - lag(Lur, 2)
  ) %>%
  filter(date >= "1975-09-01", date <= end)
fits$Lwge <- lm(y ~ c2 + c3 + c4 + c5, data = lwge)
frames$Lwge <- lwge

# ---- Headline CPI -------------------------------------------------------------------------------
pcpi <- data %>%
  mutate(
    y    = dlog(Pcpi),
    l_c  = lag(log(Pcpi / 100)),
    l_p  = lag(log(Ppcd)),
    l_tr = lag(trend),
    d_p  = dlog(Ppcd)
  ) %>%
  filter(date >= "1974-12-01", date <= end)
fits$Pcpi <- nls(
  y ~ c1 + c2 * (l_c - l_p - c3 * l_tr) + c4 * d_p +
      c6 * dum_1975q3 + c7 * dum_1976q4 + c8 * dum_2020q2,
  data = pcpi,
  start = list(c1 = 0, c2 = -0.1, c3 = 0, c4 = 1, c6 = 0, c7 = 0, c8 = 0)
)
frames$Pcpi <- pcpi

# ---- Real estate transfers deflator -------------------------------------------------------------
piret <- data %>%
  mutate(
    y  = log(Piret) - log(Pgdp),
    c3 = trend_piret
  ) %>%
  filter(date >= "1985-09-01", date <= end)
fits$Piret <- lm(y ~ c3, data = piret)
frames$Piret <- piret

# ---- Agricultural export prices -------------------------------------------------------------------
pxagr <- data %>%
  mutate(
    y  = dlog(Pxagr),
    c2 = lag(log(Pxagr)) - lag(log(Fpagr / Rusd)),
    c3 = dlog(Fpagr / Rusd),
    c4 = lag(dlog(Fpagr / Rusd)),
    c5 = dum_2009q1,
    c6 = dum_2023
  ) %>%
  filter(date >= "1975-03-01", date <= end)
fits$Pxagr <- lm(y ~ c2 + c3 + c4 + c5 + c6, data = pxagr)
frames$Pxagr <- pxagr

# ---- Import prices ----------------------------------------------------------------------------------
pmgs <- data %>%
  mutate(
    y   = dlog(Pmgs),
    l_m = lag(log(Pmgs)),
    l_w = lag(log(Fpcpi / RtwiNom)),
    l_o = lag(log(Fpoil / Rusd)),
    d_w = dlog(Fpcpi / RtwiNom),
    d_o = dlog(Fpoil / Rusd)
  ) %>%
  filter(date >= "1987-12-01", date <= end)
fits$Pmgs <- nls(
  y ~ c1 + c2 * (l_m - c3 * l_w - (1 - c3) * l_o - c4 * trend) + c5 * d_w + c6 * d_o,
  data = pmgs,
  start = list(c1 = 0, c2 = -0.1, c3 = 0.5, c4 = 0, c5 = 0, c6 = 0)
)
frames$Pmgs <- pmgs

# ---- Mortgage rate ------------------------------------------------------------------------------------
rmort <- data %>%
  mutate(
    y    = Rmort - lag(Rmort),
    l_s  = lag(Rmort) - lag(R90d),
    l_tr = lag(trend_08),
    d_r  = R90d - lag(R90d),
    d_r1 = lag(R90d) - lag(R90d, 2)
  ) %>%
  filter(date >= "1994-03-01", date <= end)
fits$Rmort <- nls(
  y ~ c1 * (l_s - c2 - c3 * l_tr) + c4 * d_r + c5 * d_r1,
  data = rmort,
  start = list(c1 = -0.1, c2 = 0, c3 = 0, c4 = 0, c5 = 0)
)
frames$Rmort <- rmort

# ---- Equity prices -------------------------------------------------------------------------------------
peqi <- data %>%
  mutate(
    y  = dlog(Peq),
    c2 = lag(dlog(Ygdp)),
    c3 = dlog(Pcpi),
    c4 = R90d - lag(R90d),
    c5 = dlog(Fpcom),
    c6 = lag(dlog(Fpcom))
  ) %>%
  filter(date >= "2004-12-01", date <= end)
fits$Peq <- lm(y ~ c2 + c3 + c4 + c5 + c6, data = peqi)
frames$Peq <- peqi

# ---- Real TWI -------------------------------------------------------------------------------------------
rtwi <- data %>%
  mutate(
    rdif = Rdif10y,
    iip  = Wfor / YgdpNom,
    y    = dlog(Rtwi),
    l_r  = lag(log(Rtwi)),
    l_p  = lag(log(Ptot)),
    l_d  = lag(rdif),
    l_i  = lag(iip),
    d_p  = dlog(Ptot),
    d_d  = rdif - lag(rdif)
  ) %>%
  filter(date >= "1981-12-01", date <= end)
fits$Rtwi <- nls(
  y ~ c1 + c2 * (l_r + c3 * l_p + c4 * l_d + c5 * l_i) + c6 * d_p + c7 * d_d,
  data = rtwi,
  start = list(c1 = 0, c2 = -0.1, c3 = 0.5, c4 = 0, c5 = 0, c6 = 0, c7 = 0)
)
frames$Rtwi <- rtwi

# ---- USD exchange rate -------------------------------------------------------------------------------------
rusd <- data %>%
  mutate(
    y  = dlog(Rusd),
    c2 = dlog(Rtwi),
    c3 = dlog(Fpcpi / Pgdp)
  ) %>%
  filter(date >= "1977-09-01", date <= end)
fits$Rusd <- lm(y ~ c2 + c3, data = rusd)
frames$Rusd <- rusd

# ---- Household net worth -------------------------------------------------------------------------------------
# Wealth accumulation: the change in net worth beyond saving is attributed to
# valuation gains from house prices, equity prices and the mortgage rate.
whh <- data %>%
  mutate(
    y  = Whh - lag(Whh) - SavHh,
    c1 = lag(Whh),
    c2 = lag(Whh) * dlog(PhouseSa),
    c3 = lag(Whh) * dlog(Peq),
    c4 = lag(Whh) * dlog(Rmort)
  ) %>%
  filter(date >= "2004-12-01", date <= end)
fits$Whh <- lm(y ~ 0 + c1 + c2 + c3 + c4, data = whh)
frames$Whh <- whh

# ---- Gross operating surplus of dwellings ----------------------------------------------------------------------
ygdw <- data %>%
  mutate(
    y   = dlog(Ygdw),
    l_g = lag(log(Ygdw)),
    l_c = lag(log(CprHpf * Ppcd)),
    d_c = dlog(CprHpf * Ppcd)
  ) %>%
  filter(date >= "1974-12-01", date <= end)
fits$Ygdw <- nls(
  y ~ c1 + c2 * (l_g - l_c - c3 * trend) + c4 * d_c,
  data = ygdw,
  start = list(c1 = 0, c2 = -0.1, c3 = 0, c4 = 0.5)
)
frames$Ygdw <- ygdw

# ---- Market-sector hours worked -----------------------------------------------------------------------------------
lhrs <- data %>%
  mutate(
    z = log(Lhrs) - log(lag(KTotal)),
    y = z - lag(z),
    lr_g = log(Ygdp) - log(lag(KTotal)),
    gap = (Ygdp - YgdpHpf) / YgdpHpf,
    rw = log(Lwge) - log(Pgdp),
    rw1 = log(lag(Lwge)) - log(lag(Pgdp)),
    ec = log(lag(Lhrs)) - log(lag(KTotal, 2))
  ) %>%
  filter(date >= "1985-06-01", date <= end)
fits$Lhrs <- nls(
  y ~ c1 * (c2 + lr_g + c4 * trend + c5 * gap + c6 * rw + c7 * rw1 - ec) +
    c8 * dum_2020q2 + c9 * dum_2020q3,
  data = lhrs,
  start = list(c1 = 0.3, c2 = 8.4, c4 = -0.003, c5 = 0.45,
               c6 = -0.69, c7 = 0.09, c8 = -0.07, c9 = 0.04)
)
frames$Lhrs <- lhrs

# ---- House prices ----------------------------------------------------------------------------------------------------
phouse <- data %>%
  mutate(
    y     = dlog(PhouseSa),
    ec    = log(lag(PhouseSa)) - log(lag(Pcpi)),
    hhkd  = log(lag(Lhh) / lag(KDwell)),
    d_p   = dlog(Pcpi),
    d_rm1 = lag(Rmort) - lag(Rmort, 2),
    d_hp1 = lag(dlog(PhouseSa)),
    d_hp2 = lag(dlog(PhouseSa), 2)
  ) %>%
  filter(date >= "2005-09-01", date <= end)
fits$Phouse <- nls(
  y ~ c1 + c2 * (ec - c3 * trend - c4 * hhkd) +
    c5 * d_p + c6 * d_rm1 + c7 * d_hp1 + c8 * d_hp2,
  data = phouse,
  start = list(c1 = 0.15, c2 = -0.30, c3 = 0.005, c4 = 0.14,
               c5 = 1.06, c6 = -1.32, c7 = 0.25, c8 = 0.37)
)
frames$Phouse <- phouse

# ---- Price deflators (long run in Balassa-Samuelson ULC + import prices) ---------------------------------------------

# Mining investment deflator
pimin <- data %>%
  mutate(
    y = dlog(Pimin), lp = lag(log(Pimin)), ulc1 = lag(UlcDom), pm1 = lag(log(Pmgs)),
    d_pm = dlog(Pmgs), d_pm2 = lag(dlog(Pmgs), 2),
    d_u = UlcDom - lag(UlcDom), d_u2 = lag(UlcDom, 2) - lag(UlcDom, 3),
    d_u3 = lag(UlcDom, 3) - lag(UlcDom, 4)
  ) %>% filter(date >= "1995-09-01", date <= end)
fits$Pimin <- nls(
  y ~ c1 + c2 * (lp - c3 * ulc1 - (1 - c3) * pm1) + c4 * d_pm + c6 * d_pm2 +
    c7 * d_u + c9 * d_u2 + c10 * d_u3 + c11 * dum_2022 + c12 * dum_2023,
  data = pimin,
  start = list(c1 = 0, c2 = -0.1, c3 = 0.5, c4 = 0, c6 = 0, c7 = 0, c9 = 0, c10 = 0, c11 = 0, c12 = 0)
)
frames$Pimin <- pimin

# Non-mining investment deflator
pinonmin <- data %>%
  mutate(
    y = dlog(Pinonmin), lp = lag(log(Pinonmin)), ulc1 = lag(UlcDom), pm1 = lag(log(Pmgs)),
    d_pm = dlog(Pmgs), d_pm1 = lag(dlog(Pmgs)), d_pm2 = lag(dlog(Pmgs), 2),
    d_u1 = lag(UlcDom) - lag(UlcDom, 2)
  ) %>% filter(date >= "1995-09-01", date <= end)
fits$Pinonmin <- nls(
  y ~ c1 + c2 * (lp - c3 * ulc1 - (1 - c3) * pm1) + c6 * d_pm + c7 * d_u1 +
    c8 * d_pm1 + c9 * d_pm2 + c10 * dum_2022 + c11 * dum_2023,
  data = pinonmin,
  start = list(c1 = 0, c2 = -0.1, c3 = 0.5, c6 = 0, c7 = 0, c8 = 0, c9 = 0, c10 = 0, c11 = 0)
)
frames$Pinonmin <- pinonmin

# Government consumption deflator
pgov <- data %>%
  mutate(
    y = dlog(Pgov), lp = lag(log(Pgov)), ulc1 = lag(UlcDom), pm1 = lag(log(Pmgs)),
    d_u = UlcDom - lag(UlcDom), d_p1 = lag(dlog(Pgov))
  ) %>% filter(date >= "1985-09-01", date <= end)
fits$Pgov <- nls(
  y ~ c1 + c2 * (lp - c3 * ulc1 - (1 - c3) * pm1) + c4 * d_u + c5 * d_p1,
  data = pgov,
  start = list(c1 = 0, c2 = -0.1, c3 = 0.5, c4 = 0, c5 = 0)
)
frames$Pgov <- pgov

# Dwelling investment deflator
pidwell <- data %>%
  mutate(
    y = dlog(Pidwell), lp = lag(log(Pidwell)), ulc1 = lag(UlcDom), pm1 = lag(log(Pmgs)),
    tr = trend, d_p1 = lag(dlog(Pidwell))
  ) %>% filter(date >= "1995-09-01", date <= end)
fits$Pidwell <- nls(
  y ~ c1 + c2 * (lp - c3 * ulc1 - (1 - c3) * pm1 - c4 * tr) +
    c5 * dum_2000q3 + c6 * d_p1 + c7 * dum_2000q4,
  data = pidwell,
  start = list(c1 = -0.13, c2 = -0.03, c3 = 0.66, c4 = 0.0036, c5 = 0.06, c6 = 0.88, c7 = -0.08)
)
frames$Pidwell <- pidwell

# Services export deflator
pxsvc <- data %>%
  mutate(
    y = dlog(Pxsvc), lp = lag(log(Pxsvc)), ulcx1 = lag(UlcExp), tr = trend,
    d_u = UlcExp - lag(UlcExp), d_u1 = lag(UlcExp) - lag(UlcExp, 2)
  ) %>% filter(date >= "1995-12-01", date <= end)
fits$Pxsvc <- nls(
  y ~ c1 + c2 * (lp - ulcx1 - c4 * tr) + c5 * d_u + c6 * d_u1,
  data = pxsvc,
  start = list(c1 = 0, c2 = -0.1, c4 = 0, c5 = 0, c6 = 0)
)
frames$Pxsvc <- pxsvc

# ---- Personal income tax -------------------------------------------------------------
tpit <- data %>%
  mutate(
    y   = dlog(Tpit),
    ec  = lag(log(Tpit)) - lag(log(Ynli)),
    d_u = dlog(Lur),  d_u1 = lag(dlog(Lur)),
    d_w = lag(dlog(Lwge)),
    d_t = lag(dlog(Tpit))
  ) %>% filter(date >= "1975-03-01", date <= end)
fits$Tpit <- nls(y ~ c1 + c2 * ec + c4 * d_u + c5 * d_u1 + c6 * d_w + c7 * d_t + c8 * dum_2000q3,
    data = tpit,
    start = list(c1 = -0.22, c2 = -0.12, c4 = -0.18, c5 = -0.19, c6 = 1.10, c7 = -0.24, c8 = -0.25))
frames$Tpit <- tpit

# ---- Public sector net debt -------------------------------------------------------------
govdebt <- data %>%
  mutate(y = GovDebt - lag(GovDebt) - GovDef,
         x = lag(R10y, 5) * lag(GovDebt)) %>%
  filter(date >= "2004-09-01", date <= end)
fits$GovDebt <- lm(y ~ 0 + x, data = govdebt)
frames$GovDebt <- govdebt

# ---- Rents ----------------------------------------------------------------------------------
prent <- data %>%
  mutate(
    y    = dlog(PcpiRent),
    ec_p = lag(log(PcpiRent)) - lag(log(PhouseHpf)),
    rm_h = lag(RmortRealHpf),
    nom  = Lnom / 1e3,
    d_w  = dlog(Lwge), d_w1 = lag(dlog(Lwge)),
    d_p1 = lag(dlog(PcpiRent))
  ) %>% filter(date >= "2004-12-01", date <= end)
fits$PcpiRent <- nls(y ~ c1 + c2 * (ec_p - c4 * rm_h) + c5 * nom + c6 * d_w + c7 * d_w1 + c8 * d_p1,
    data = prent,
    start = list(c1 = -0.04, c2 = -0.04, c4 = 24, c5 = 0.03, c6 = -0.08, c7 = 0.10, c8 = 0.56))
frames$PcpiRent <- prent

# ---- Non-mining investment ---------------------------------------------------------------------
inonmin <- data %>%
  mutate(
    y   = dlog(Inonmin),
    c2  = lag(log(Inonmin)) - lag(log(Ygne)) +
            0.6 * log(lag(CostCap)) +
            (log(lag(Pinonmin)) - log(lag(Pgne))),
    c5  = dlog(Ygne),
    c6  = lag(dlog(Ygne)),
    c7  = lag(dlog(Ygne), 2),
    c8  = lag(dlog(Ygne), 3),
    c9  = lag(dlog(Inonmin)),
    c10 = dum_2012q4,
    c11 = dlog(Pinonmin)
  # This window previously ended at the 2024Q3 coefficient vintage; it now
  # follows the data end, and the resulting coefficient changes are surfaced
  # by the comparison written to outputs/coefficient_comparison.csv.
  ) %>% filter(date >= "2002-03-01", date <= end)
fits$Inonmin <- lm(y ~ c2 + c5 + c6 + c7 + c8 + c9 + c10 + c11, data = inonmin)
frames$Inonmin <- inonmin

# ---- Non-labour household income ratio ------------------------------------------------------------
ynli <- data %>%
  mutate(
    ratio = Ynli / (YgdpNom - Ywss - Ygdw),
    l_r   = lag(ratio),
    rm    = Rmort,
    pe    = EqYield,
    pe1   = lag(EqYield),
    pe2   = lag(EqYield, 2),
    pe3   = lag(EqYield, 3)
  ) %>% filter(date >= "1997-06-01", date <= end)
fits$Ynli <- lm(ratio ~ rm + pe + pe1 + pe2 + pe3 + l_r, data = ynli)
frames$Ynli <- ynli

# ---- Listed-company earnings -----------------------------------------------------------------------
eqi <- data %>%
  mutate(
    y     = dlog(EqEarn),
    rc    = log(Fpcom / Pgdp),   rc1 = lag(rc),
    ec    = lag(log(EqEarn)) - lag(log(Ygoa)),
    rus1  = lag(Rusd, 2),
    d_rc  = rc - lag(rc),
    d_ru1 = lag(Rusd) - lag(Rusd, 2),
    d_g   = dlog(Ygoa),  d_g1 = lag(dlog(Ygoa)),
    d_g2  = lag(dlog(Ygoa), 2), d_g3 = lag(dlog(Ygoa), 3), d_g4 = lag(dlog(Ygoa), 4)
  ) %>% filter(date >= "2004-12-01", date <= end)
fits$EqEarn <- nls(y ~ c1 + c2 * (ec - c3 * rc1 - c4 * rus1 - c5 * trend) +
        c7 * d_rc + c8 * d_ru1 + c9 * d_g + c10 * d_g1 + c11 * d_g2 + c12 * d_g3 + c13 * d_g4,
      data = eqi,
      start = list(c1 = -1.19, c2 = -0.31, c3 = 0.51, c4 = -1.58, c5 = -0.009,
                   c7 = 0.11, c8 = -0.95, c9 = 0.04, c10 = 0.27, c11 = -0.12, c12 = 0.34, c13 = 0.49))
frames$EqEarn <- eqi

# ---- GST -------------------------------------------------------------------------------------------
tgst <- data %>%
  mutate(
    y   = dlog(Tgst),
    ec  = lag(log(Tgst)) - lag(log(CprNom)),
    d0  = dlog(CprNom),  d1 = lag(dlog(CprNom)),
    d2  = lag(dlog(CprNom), 2), d3 = lag(dlog(CprNom), 3), d4 = lag(dlog(CprNom), 4)
  ) %>% filter(date >= "2001-03-01", date <= end)
  fits$Tgst <- nls(y ~ c1 + c2 * (ec - c3 * ShockGst - c4 * trend) + c5 * d0 + c6 * d1 + c7 * d2 + c8 * d3 + c9 * d4,
    data = tgst,
    start = list(c1 = -0.18, c2 = -0.08, c3 = 0.05, c4 = -0.002, c5 = 0.73,
                 c6 = -0.08, c7 = -0.12, c8 = -0.17, c9 = -0.18))
frames$Tgst <- tgst

# ---- Other goods exports ------------------------------------------------------------------------------
xoth <- data %>%
  mutate(
    y   = dlog(Xoth),
    ec  = lag(log(Xoth)) - lag(log(Ygdp)),
    rel = lag(Pxoth / Pgdp),
    d_r = (Pxoth / Pgdp) - lag(Pxoth / Pgdp),
    d_g = dlog(Ygdp)
  ) %>% filter(date >= "1985-12-01", date <= end)
fits$Xoth <- nls(y ~ c1 + c2 * (ec - c3 * rel - c4 * sb_2001 - c5 * sb_2001 * trend) + c6 * d_r + c7 * d_g,
    data = xoth,
    start = list(c1 = -0.14, c2 = -0.05, c3 = -0.15, c4 = 0.7, c5 = 0, c6 = -0.15, c7 = 0.95))
frames$Xoth <- xoth

# ---- Mining export deflator -------------------------------------------------------------------------------
pxmin <- data %>%
  mutate(
    y   = dlog(Pxmin),
    ec  = lag(log(Pxmin)) - lag(log(Fpcom / Rusd)),
    d_f = dlog(Fpcom),
    d_u = dlog(Rusd)
  ) %>% filter(date >= "1989-12-01", date <= end)
fits$Pxmin <- nls(y ~ c1 + c2 * ec + c3 * d_f + c4 * d_u,
    data = pxmin,
    start = list(c1 = -0.04, c2 = -0.12, c3 = 0.40, c4 = -1.27))
frames$Pxmin <- pxmin

# ---- Other-exports deflator ----------------------------------------------------------------------------------
pxoth <- data %>%
  mutate(
    y     = dlog(Pxoth),
    lp    = lag(log(Pxoth)),
    ulcx1 = lag(UlcExp),
    pm1   = lag(log(Pmgs)),
    t     = lag(trend),
    d_ulcx = UlcExp - lag(UlcExp),
    d_pm = dlog(Pmgs)
  ) %>% filter(date >= "1989-12-01", date <= end)
fits$Pxoth <- nls(y ~ c1 + c2 * (lp - c3 * ulcx1 - (1 - c3) * pm1 - c4 * t) + c5 * d_ulcx + c6 * d_pm,
    data = pxoth,
    start = list(c1 = -1.03, c2 = -0.31, c3 = 0.77, c4 = 0.68, c5 = -0.52, c6 = -0.11))
frames$Pxoth <- pxoth

# ---- Ex-rent consumption deflator -------------------------------------------------------------------------------
pcnh <- data %>%
  mutate(
    y     = dlog(PconsExrent),
    lp    = lag(log(PconsExrent)),
    ulc1  = lag(UlcDom),
    pm1   = lag(log(Pmgs)),
    gap   = (Lur - LurHpf) / Lur,
    d_ulc = UlcDom - lag(UlcDom),
    d_pm  = dlog(Pmgs),
    d_lu  = dlog(Lur)
  ) %>% filter(date >= "1995-09-01", date <= end)
fits$PconsExrent <- nls(y ~ c1 + c2 * (lp - c3 * ulc1 - (1 - c3) * pm1) + c4 * gap +
      c5 * d_ulc + c6 * d_pm + c9 * dum_2000q3 + c10 * d_lu,
    data = pcnh,
    start = list(c1 = -0.24, c2 = -0.08, c3 = 0.65, c4 = -0.008,
                 c5 = 0.021, c6 = 0.026, c9 = 0.021, c10 = -0.38))
frames$PconsExrent <- pcnh

# ---- Consumption deflator split (ex-rent weight) ------------------------------------------------------------------
ppcd <- data %>%
  mutate(y = dlog(Ppcd), a = dlog(PconsExrent), b = dlog(PconsRent)) %>%
  filter(date >= "1974-12-01", date <= end)
fits$Ppcd <- nls(y ~ c1 * a + (1 - c1) * b, data = ppcd, start = list(c1 = 0.8))
frames$Ppcd <- ppcd

# ---- Services exports -----------------------------------------------------------------------------------------------
xsvc <- data %>%
  mutate(
    y    = dlog(Xsvc),
    l_x  = lag(log(Xsvc)),
    l_g  = lag(log(Ygdp)),
    rel  = lag(Pxsvc / Pgdp),
    l_s  = lag(log(IntStu)),
    d_r  = (Pxsvc / Pgdp) - lag(Pxsvc / Pgdp),
    d_g  = dlog(Ygdp),
    d_s  = dlog(IntStu)
  ) %>% filter(date >= "2006-03-01", date <= end)
fits$Xsvc <- nls(
  y ~ c1 + c2 * (l_x - l_g - c3 * rel - c4 * l_s) + c5 * d_r + c6 * d_g + c7 * d_s +
      c8 * dum_2020q1 + c9 * dum_2020q2 + c10 * dum_2020q3,
  data = xsvc,
  start = list(c1 = 0, c2 = -0.1, c3 = 0, c4 = 0.7, c5 = 0, c6 = 1.5, c7 = 0.2,
               c8 = -0.1, c9 = -0.1, c10 = -0.1)
)
frames$Xsvc <- xsvc

# ---- Imports of goods and services ------------------------------------------------------------------------------------
md <- data %>%
  mutate(y = dlog(Mtot), l_m = lag(log(Mtot)), l_d = lag(log(Ygne)),
         rel = lag(Pmgs * 100 / Pgne),
         d_g = dlog(Ygne),
         d_g1 = lag(dlog(Ygne)),
         d_r = (Pmgs / Pgne) - lag(Pmgs / Pgne)) %>%
  filter(date >= "1975-03-01", date <= end)
# Specification as estimated: the long-run relative price carries a x100
# level factor while the short-run change does not.
fits$Mtot <- nls(
  y ~ c1 + c2 * (l_m - l_d - c3 * rel) + c4 * d_g + c5 * d_g1 + c6 * d_r,
  data = md,
  start = list(c1 = 0, c2 = -0.1, c3 = -0.4, c4 = 0.004, c5 = 1.1, c6 = -0.2)
)
frames$Mtot <- md

# ---- Cash rate (state-space reaction function) ---------------------------------------------------------------------------
# Emma/Martin specification: reaction coefficients are imposed; only the
# latent-state and observation variances are estimated.
rc <- data %>%
  mutate(inf = Pcpi / lag(Pcpi, 4) - 1,
         dr = R90d - lag(R90d),
         gap = Lur - LurHpf,
         dlur = Lur - lag(Lur),
         r_lag = lag(R90d)) %>%
  filter(!is.na(dr), !is.na(inf), !is.na(gap), !is.na(dlur), date >= "1976-03-01") %>%
  select(date, dr, inf, gap, dlur, r_lag, d93)

kalman_nll <- function(theta) {
  c1 <- RCASH_IMPOSED[["c1"]]; c2 <- RCASH_IMPOSED[["c2"]]
  c3 <- RCASH_IMPOSED[["c3"]]; c4 <- RCASH_IMPOSED[["c4"]]
  Q  <- exp(2 * theta[1]); H <- exp(2 * theta[2])
  a <- 0; P <- 100
  ll <- 0
  for (i in seq_len(nrow(rc))) {
    a_pred <- a; P_pred <- P + Q
    yhat <- c1 * (a_pred + rc$inf[i] + c2 * rc$gap[i] +
                  c3 * rc$d93[i] * (rc$inf[i] - 0.025) - rc$r_lag[i]) +
            c4 * rc$dlur[i]
    F <- c1^2 * P_pred + H
    v <- rc$dr[i] - yhat
    K <- c1 * P_pred / F
    a <- a_pred + K * v
    # Algebraically equivalent scalar Kalman covariance update. This form
    # avoids cancellation that can make P (and then F) spuriously negative
    # while optim() explores the likelihood surface.
    P <- P_pred * H / F
    ll <- ll - 0.5 * (log(2 * pi * F) + v^2 / F)
  }
  -ll
}

variance_fit <- optim(c(log(0.3), log(0.3)), kalman_nll, method = "BFGS",
                      control = list(maxit = 300))
names(variance_fit$par) <- c("log_sig_state", "log_sig_obs")
variance_se <- tryCatch(
  sqrt(diag(solve(optimHess(variance_fit$par, kalman_nll)))),
  error = function(e) rep(NA_real_, length(variance_fit$par))
)
opt <- variance_fit
opt$par <- c(RCASH_IMPOSED, variance_fit$par)
opt$std_error <- c(stats::setNames(rep(NA_real_, 4), names(RCASH_IMPOSED)),
                   stats::setNames(variance_se, names(variance_fit$par)))
fits$Rcash <- opt

# RTS smoother pass to recover the smoothed neutral rate (Rstar)
c1 <- opt$par[1]; c2 <- opt$par[2]; c3 <- opt$par[3]; c4 <- opt$par[4]
Q  <- exp(2 * opt$par[5]); H <- exp(2 * opt$par[6])
n_rc <- nrow(rc); a_f <- numeric(n_rc); P_f <- numeric(n_rc)
a <- 0; P <- 100
for (i in seq_len(n_rc)) {
  a_pred <- a; P_pred <- P + Q
  yhat <- c1 * (a_pred + rc$inf[i] + c2 * rc$gap[i] +
                c3 * rc$d93[i] * (rc$inf[i] - 0.025) - rc$r_lag[i]) + c4 * rc$dlur[i]
  F <- c1^2 * P_pred + H
  v <- rc$dr[i] - yhat
  K <- c1 * P_pred / F
  a <- a_pred + K * v
  P <- P_pred * H / F
  a_f[i] <- a; P_f[i] <- P
}
a_s <- a_f
for (i in (n_rc - 1):1) {
  J <- P_f[i] / (P_f[i] + Q)
  a_s[i] <- a_f[i] + J * (a_s[i + 1] - a_f[i])
}
data$Rstar <- NA_real_
data$Rstar[match(rc$date, data$date)] <- a_s

# ---- 10-year bond rate ------------------------------------------------------------------------------------------------------
r10y <- data %>%
  mutate(y = R10y, l = lag(R10y), rat = Rstar + InflExp,
         dy = y - l, d_rat = rat - l, d_r90 = R90d - l) %>%
  filter(!is.na(y), !is.na(l), !is.na(rat), !is.na(R90d)) %>%
  filter(date >= "1976-03-01", date <= end)
fits$R10y <- lm(dy ~ d_rat + d_r90, data = r10y)
frames$R10y <- r10y

list(fits = fits, frames = frames, data = data, bs_c2 = attr(data, "bs_c2"))
}
