library(tidyverse)
library(readxl)
library(seasonal)

hp_filter <- function(x, lambda = 1600) {
  ok <- which(is.finite(x))
  n <- length(ok)
  if (n < 3L) return(rep(NA_real_, length(x)))
  D <- diff(diag(n), differences = 2)
  out <- rep(NA_real_, length(x))
  out[ok] <- solve(diag(n) + lambda * crossprod(D), x[ok])
  out
}

# Prepare the estimation dataset from the authoritative workbook.
# Returns a quarterly tibble covering the full input history; estimation and
# forecast stages receive it in memory (nothing is written to disk).
#
# Naming conventions (see VARIABLES.md):
#   UpperCamelCase series; `Nom` = current-price counterpart of a volume
#   series; `Real` = real counterpart of a nominal rate; `Hpf` = HP-filtered
#   trend; deterministic terms are lowercase (trend_98, dum_2020q2, q3, d93).
#   Annual or benchmark-frequency inputs are interpolated to quarterly IN
#   PLACE under a single name (IntStu, K stocks, GovDebt, GovDef, Lhh).
calculate_estimation_data <- function(path = "data-raw/Data.xlsx") {

# X-13ARIMA-SEATS seasonal adjustment of a quarterly series in `data` order.
# Operates on the contiguous observed span, returns NA elsewhere, and falls
# back to the original series if X-13 fails to converge.
sa_series <- function(x, dates) {
  ok <- which(!is.na(x))
  if (length(ok) < 16) return(x)
  span <- ok[1]:ok[length(ok)]
  xt <- ts(x[span],
           start = c(lubridate::year(dates[span[1]]),
                     lubridate::quarter(dates[span[1]])),
           frequency = 4)
  adj <- tryCatch(as.numeric(final(seas(xt))), error = function(e) NULL)
  if (is.null(adj) || length(adj) != length(span)) {
    warning("seasonal adjustment failed; series left unadjusted")
    return(x)
  }
  out <- rep(NA_real_, length(x))
  out[span] <- adj
  out
}

data <- read_excel(path, sheet = "Data") %>%
  filter(!is.na(date)) %>%
  mutate(date = as.Date(date))

# ---- World CPI: remove the spurious 2009 level break ----------------------
# Fpcpi rises 6-7% in each quarter of 2009 (about 27% over the year) and then
# reverts to its usual 0.5-1% a quarter. World CPI inflation in 2009 was near
# zero (the GFC trough), so the step is an un-chain-linked rebasing in the
# source, smeared across a year. Keep the post-break level (the vintage the
# model runs on), lift the earlier history onto it, and replace 2009 with a
# constant-growth ramp at the average of the surrounding rates. Fpcpi enters
# Rtwi as a level and Fr10yReal as a growth rate, so both the step and the
# level discontinuity matter.
fp_brk  <- which(data$date >= as.Date("2009-03-01") &
                   data$date <= as.Date("2009-12-01"))
fp_g    <- c(NA, diff(log(data$Fpcpi)))
fp_ref  <- which((data$date >= as.Date("2007-03-01") &
                    data$date <= as.Date("2008-12-01")) |
                   (data$date >= as.Date("2010-03-01") &
                      data$date <= as.Date("2011-12-01")))
fp_norm <- mean(fp_g[fp_ref], na.rm = TRUE)
fp_exc  <- sum(fp_g[fp_brk], na.rm = TRUE) - fp_norm * length(fp_brk)
if (length(fp_brk) == 4 && fp_exc > 0.1) {
  fp_pre <- which(data$date < data$date[fp_brk[1]])
  data$Fpcpi[fp_pre] <- data$Fpcpi[fp_pre] * exp(fp_exc)
  fp_anchor <- data$Fpcpi[fp_brk[1] - 1]
  data$Fpcpi[fp_brk] <- fp_anchor * exp(fp_norm * seq_along(fp_brk))
}
rm(fp_brk, fp_g, fp_ref, fp_norm, fp_exc)

# ---- Capital stock depreciation rates ---------------------------------------
# Quarterly rates implied by the model's own investment:
# DepRate_t = 1 - (K_t - I_{t-1}) / K_{t-1}. KOther has no matching
# investment series, so no rate is formed.
data <- data %>%
  mutate(
    KMinDepRate   = 1 - (KMin   - lag(Imin))    / lag(KMin),
    KNbizDepRate  = 1 - (KNbiz  - lag(Inonmin)) / lag(KNbiz),
    KDwellDepRate = 1 - (KDwell - lag(Idwell))  / lag(KDwell)
  )

data <- data %>%
  mutate(
    # ---- Expenditure and trade aggregates --------------------------------
    Ivt      = IvtFar + IvtNonfarm,
    Xmin     = Xmet + Xccb + Xomf,
    XminNom  = XmetNom + XccbNom + XomfNom,
    Xoth     = Xmex + Xmac + Xtrn + Xotm + Xonr + Xgpr,
    XothNom  = XmexNom + XmacNom + XtrnNom + XotmNom + XonrNom + XgprNom,
    # ---- Taxes ------------------------------------------------------------
    # Toth is the residual of total taxes once the named heads are removed.
    Toth     = Ttot - Tpit - Tcit - Tgst - Tprl,
    # ---- Deflators (implicit price deflators from nominal/volume pairs) ---
    Pxoth    = XothNom / Xoth,
    Ppcd     = CprNom / Cpr,
    Pgdp     = YgdpNom / Ygdp,
    Pmgs     = MtotNom / Mtot,
    Pidwell  = IdwellNom / Idwell,
    Piret    = IotcNom / Iotc,
    Pxtot    = XtotNom / Xtot,
    Pxagr    = XagrNom / Xagr,
    Pxmin    = XminNom / Xmin,
    Pgov     = CgovNom / Cgov,
    Pimin    = IminNom / Imin,
    Pinonmin = InonminNom / Inonmin,
    PconsRent    = CconsRentNom / CconsRent,
    PconsExrent  = (CprNom - CconsRentNom) / (Cpr - CconsRent),
    # ---- Labour market -----------------------------------------------------
    Lur      = Lune / Lsup,
    LempNonmkt = LempPub + LempEdu + LempHlt,
    LempMkt    = Lemp - LempNonmkt,
    # ---- Hours worked -------------------------------------------------------
    # The ABS hours series are published unadjusted while the employment
    # series are seasonally adjusted; seasonally adjust the hours aggregates
    # with X-13 so numerator and denominator are on the same basis.
    LhrsNonmkt = sa_series(LhrsPub + LhrsEdu + LhrsHlt, date),
    LhrsAllSa  = sa_series(LhrsAll, date),
    Lhrs       = LhrsAllSa - LhrsNonmkt,
    # ---- Cost of capital ----------------------------------------------------
    # Jorgensonian user cost: a real after-tax business lending rate and an
    # equity earnings yield weighted by the debt share of business finance,
    # plus the depreciation rate, all scaled by the tax value of the
    # depreciation allowance.
    EqYield   = 1 / PeRatio,
    BizGear   = (BizLns + BizBnd) / (BizLns + BizBnd + BizEq),
    RbizReal  = (1 - TcorpRate) * Rbiz / (PconsExrent / lag(PconsExrent, 4)),
    KdepAllow = (KdepRate * (1 + R10y)) * (R10y + KdepRate),
    CostCap   = (RbizReal * BizGear + EqYield * (1 - BizGear) + KdepRate) *
                  (1 - KdepAllow * TcorpRate),
    # ---- Household income ---------------------------------------------------
    Ynli      = Ygmi + YprpR - YprpP,
    # ---- Public sector -------------------------------------------------------
    GovDem    = Igov + Ipubent + Cgov,
    # ---- House prices ----------------------------------------------------------
    PhouseSa   = sa_series(Phouse, date),
    PhouseReal = PhouseSa / Pcpi,
    # ---- Interest and exchange rates ---------------------------------------------
    Rtwi          = RtwiNom * lag(PcpiExGst) / lag(Fpcpi),
    R90dReal      = R90d - (Pcpi / lag(Pcpi, 4) - 1),
    Fr10y         = (3 / 5) * Fr10yUs + (1 / 6) * Fr10yJp +
                    (1 / 12) * Fr10yUk + (3 / 20) * Fr10yDe,
    Fr10yReal     = Fr10y - ((lag(Fpcpi, 2) / lag(Fpcpi, 6) - 1) +
                              (lag(Fpcpi, 6) / lag(Fpcpi, 10) - 1)) / 2,
    Rdif10y       = R10yReal - Fr10yReal,
    RmortReal     = Rmort - (Pcpi / lag(Pcpi, 4) - 1),
    RmortRealExgst = Rmort - (PcpiExGst / lag(PcpiExGst, 4) - 1),
    # ---- Trend measures ---------------------------------------------------------
    InflExp     = hp_filter(log(Pcpi / lag(Pcpi, 4))),
    CprHpf      = hp_filter(Cpr),
    PhouseHpf   = hp_filter(PhouseSa),
    LurHpf      = hp_filter(Lur),
    YgdpHpf     = hp_filter(Ygdp),
    RmortRealHpf = hp_filter(RmortReal),
    # ---- Terms of trade ----------------------------------------------------------
    Ptot        = 100 * Pxtot / Pmgs
  )

# ---- Deterministic terms ----------------------------------------------------
data <- data %>%
  mutate(
    trend        = row_number() - 1,
    # The Piret equation's trend has its origin eight quarters before the
    # 1974Q3-based trend; the shift is kept with the deterministic terms.
    trend_piret  = trend + 8,
    trend_98     = cumsum(date >= "1998-03-01"),
    trend_01     = cumsum(date >= "2001-03-01"),
    trend_08     = cumsum(date >= "2008-03-01"),
    d93          = as.numeric(date >= "1993-03-01"),   # inflation targeting
    q3           = as.numeric(month(date) == 9),
    ShockGst     = as.numeric(ShockGst),
    dum_1975q3   = as.numeric(date == "1975-09-01"),
    dum_1976q4   = as.numeric(date == "1976-12-01"),
    dum_2009q1   = as.numeric(date == "2009-03-01"),
    dum_2020q1   = as.numeric(date == "2020-03-01"),
    dum_2020q2   = as.numeric(date == "2020-06-01"),
    dum_2020q3   = as.numeric(date == "2020-09-01"),
    dum_2020q4   = as.numeric(date == "2020-12-01"),
    dum_2021q1   = as.numeric(date == "2021-03-01"),
    dum_2000q3   = as.numeric(date == "2000-09-01"),
    dum_2000q4   = as.numeric(date == "2000-12-01"),
    dum_2012q4   = as.numeric(date == "2012-12-01"),
    dum_2022q1   = as.numeric(date == "2022-03-01"),
    dum_2022     = as.numeric(year(date) == 2022),
    dum_2023     = as.numeric(year(date) == 2023),
    sb_2001      = as.numeric(date >= "2002-03-01"),
    dum_covid_cpr = as.numeric(between(date, as.Date("2020-03-01"), as.Date("2022-03-01"))),
    dum_covid_avh = as.numeric(between(date, as.Date("2020-03-01"), as.Date("2022-09-01"))),
    LparHpf      = hp_filter(Lpar),
    PpcdHpf      = hp_filter(Ppcd)
  )

# ---- Balassa-Samuelson unit labour costs ------------------------------------
# The state equations are deterministic given c2, so the system collapses to
# a non-linear least squares problem in the signal equation:
#   log(Ppcd) = c1 + c2*log(Pulc) + 0.002764*(1 - c2)*trend + (1 - c2)*log(Pmgs)
# where 0.002764 is the quarterly productivity differential. UlcDom is the
# domestic-cost concept used by the investment deflators; UlcExp is the
# traded-sector concept used by the export deflators.
BS_PARAM <- 0.002764
bs_dat <- data %>%
  transmute(lp = log(Ppcd), lu = log(Pulc), lm = log(Pmgs), tr = trend) %>%
  filter(if_all(everything(), is.finite))
bs_fit <- nls(
  lp ~ c1 + c2 * lu + BS_PARAM * (1 - c2) * tr + (1 - c2) * lm,
  data = bs_dat, start = list(c1 = 0, c2 = 0.65)
)
bs_c2 <- coef(bs_fit)[["c2"]]
data$UlcDom <- log(data$Pulc) + BS_PARAM * ((1 - bs_c2) / bs_c2) * data$trend
data$UlcExp <- log(data$Pulc) - BS_PARAM * data$trend
attr(data, "bs_c2") <- bs_c2
message(sprintf("Balassa-Samuelson signal equation: c(2) = %.4f", bs_c2))

data
}
