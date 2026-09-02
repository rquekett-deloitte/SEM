# BIMETS model: equations + identities + database + simulation.
#
# Equations are transcriptions of R/estimation.R (the source of truth) with
# the estimated coefficients injected as numbers (the error-correction
# specs are nonlinear in their coefficients, which bimets' symbolic
# BEHAVIORAL form does not accept). Identities continue the data-preparation
# definitions in R/calculate_estimation_data.R plus the expenditure/nominal
# sums and the documented forecast-closure rules in VARIABLES.md. Scenario
# inputs are declared explicitly by mdl_exogenous_contract(); an omitted model
# variable is never silently promoted to exogenous status.

library(tidyverse)
library(bimets)

# ---- behavioural equations (one per fitted equation) --------------------------

mdl_equations <- function() { c(
"Cpr = Cpr[1]*EXP( Cpr_c1 + Cpr_c2*(LOG(Cpr[1]) - Cpr_c3*LOG(Yhdi[1]/Pgdp[1]) - (1-Cpr_c3)*LOG(Whh[1]/Pgdp[1]) + 0.5*R90dReal[1]) + Cpr_c6*(LOG(Whh)-LOG(Whh[1])) + Cpr_c8*(LOG(Yhdi)-LOG(Yhdi[1])) + Cpr_c9*(LOG(Yhdi[1])-LOG(Yhdi[2])) + Cpr_c10*(LOG(Yhdi[2])-LOG(Yhdi[3])) + Cpr_c11*4*(Lur-Lur[1]) + Cpr_c12*CprDum )",

"Idwell = Idwell[1]*EXP( Idwell_c1 + Idwell_c2*(LOG(Idwell[1]) - LOG(Cpr[1]) - Idwell_c4*(LOG(Pidwell[1])-LOG(Ppcd[1])) - Idwell_c5*RmortRealExgst[1]) + Idwell_c7*(LOG(PhouseReal[1])-LOG(PhouseReal[2])) + Idwell_c8*(LOG(PhouseReal[2])-LOG(PhouseReal[3])) + Idwell_c9*(LOG(PhouseReal[3])-LOG(PhouseReal[4])) + Idwell_c10*(LOG(PhouseReal[4])-LOG(PhouseReal[5])) + Idwell_c11*Dum2020q2 + Idwell_c13*Dum2020q4 + Idwell_c14*Dum2021q1 )",

"Imin = Imin[1]*EXP( Imin_c1 + Imin_c2*(LOG(Imin[1]) - LOG(Ygdp[1]) - Imin_c3*LOG(Pxmin[1]/Pgdp[1])) + Imin_c4*(LOG(Pxmin)-LOG(Pxmin[1])) + Imin_c5*(LOG(Pxmin[1])-LOG(Pxmin[2])) + Imin_c6*(LOG(Pxmin[2])-LOG(Pxmin[3])) + Imin_c7*(LOG(Imin[1])-2*LOG(Imin[2])+LOG(Imin[3])) )",

"IvtNonfarm = IvtNonfarm[1]*EXP( IvtNonfarm_c1 + IvtNonfarm_c2*(LOG(IvtNonfarm[1]) - LOG(Ygdp[1]) + IvtNonfarm_c3*TrendIvt + IvtNonfarm_c4*TrendIvt*TrendIvt + IvtNonfarm_c5*TrendIvt*TrendIvt*TrendIvt) + IvtNonfarm_c6*(LOG(IvtNonfarm[1])-LOG(IvtNonfarm[2])) + IvtNonfarm_c7*(LOG(IvtNonfarm[2])-LOG(IvtNonfarm[3])) + IvtNonfarm_c8*(LOG(Ygdp[1])-LOG(Ygdp[2])) )",

"Tcit = Tcit[1]*EXP( Tcit_c1 + Tcit_c2*(LOG(Tcit[1]) - LOG(Ygoa[1]) - Tcit_c5*LOG(Ptot[1])) + Tcit_c6*(LOG(Ygoa)-LOG(Ygoa[1])) + Tcit_c7*((LOG(Fpcom)-LOG(Fpcom[1]))-(LOG(ABS(Pgdp))-LOG(Pgdp[1]))) )",

"Tprl = Tprl[1]*EXP( Tprl_Int + Tprl_c2*(LOG(Tprl[1])-LOG(Ywss[1])) + Tprl_c4*(Lur-LurHpf) + Tprl_c5*(LOG(Lemp[1])-4*LOG(Lemp[2])+6*LOG(Lemp[3])-4*LOG(Lemp[4])+LOG(Lemp[5])) )",

"Toth = Toth[1]*EXP( Toth_c1 + Toth_c2*(LOG(Toth[1]) - LOG(YgdpNom[1]) - Toth_c3*ShockGst[1]) + Toth_c4*(LOG(YgdpNom)-LOG(YgdpNom[1])) )",

"Ytsf = Ytsf[1]*EXP( Ytsf_c1 + Ytsf_c2*(LOG(Ytsf[1]) - Ytsf_c3*LOG(YgdpNom[1]) - (1-Ytsf_c3)*LOG(Lune[1]*Pcpi[1])) + Ytsf_c4*(LOG(Lemp)-LOG(Lemp[1])) + Ytsf_c5*(Lur[1]-LurHpf[1]) + Ytsf_c6*Q3ind + Ytsf_c7*DumTsfTot )",

"Xmin = Xmin[1]*EXP( Xmin_Int + Xmin_c2*(LOG(Xmin[1])-LOG(KMin[1])) + Xmin_c3*(LOG(Xmin[1])-LOG(Xmin[2])) + Xmin_c4*(LOG(FcGdp[1])-LOG(FcGdp[2])) + Xmin_c5*(LOG(FcGdp[2])-LOG(FcGdp[3])) + Xmin_c6*(LOG(FcGdp[3])-LOG(FcGdp[4])) + Xmin_c7*(LOG(FcPpp[1])-LOG(FcPpp[2])) + Xmin_c8*(LOG(FcPpp[2])-LOG(FcPpp[3])) + Xmin_c9*(LOG(FcPpp[3])-LOG(FcPpp[4])) + Xmin_c10*(LOG(Fpcom[1])-LOG(Fpcom[2])) + Xmin_c11*(LOG(Fpcom[2])-LOG(Fpcom[3])) + Xmin_c12*(LOG(Fpcom[3])-LOG(Fpcom[4])) )",

"LavhMkt = Lavh_rho*LavhMkt[1] + (1-Lavh_rho)*Lavh_c1 + Lavh_c2*(GapAvh - Lavh_rho*GapAvh[1]) + Lavh_c3*(LavhDum - Lavh_rho*LavhDum1) + Lavh_c4*(Trend98 - Lavh_rho*Trend98[1])",

"LempNonmkt = EXP( LempNonmkt_Int + LempNonmkt_c2*LOG(LempMkt) + LempNonmkt_c3*Trend01 + LempNonmkt_c4*LOG(GovDem) )",

"Lpar = Lpar[1] + Lpar_Int + Lpar_c2*(Lpar[1]-LparHpf[1]) + Lpar_c3*(Lur-LurHpf) + Lpar_c4*(Lur-Lur[1]) + Lpar_c5*(Lur[1]-Lur[2]) + Lpar_c6*(Lwge[1]/Pcpi[1]-Lwge[5]/Pcpi[5]) + Lpar_c7*Dum2020q2 + Lpar_c8*Dum2020q3 + Lpar_c9*Dum2020q4",

"Lwge = Lwge[1]*EXP( Lwge_Int + Lwge_c2*((LOG(Ppcd[3])-LOG(Ppcd[4]))-(LOG(PpcdHpf)-LOG(PpcdHpf[1]))) + Lwge_c3*(Lur-LurHpf)/Lur + Lwge_c4*(Lur-Lur[1]) + Lwge_c5*(Lur[1]-Lur[2]) + (LOG(PpcdHpf)-LOG(PpcdHpf[1])) )",

"Pcpi = Pcpi[1]*EXP( Pcpi_c1 + Pcpi_c2*(LOG(Pcpi[1]/100) - LOG(Ppcd[1]) - Pcpi_c3*Trend[1]) + Pcpi_c4*(LOG(Ppcd)-LOG(Ppcd[1])) + Pcpi_c6*Dum1975q3 + Pcpi_c7*Dum1976q4 + Pcpi_c8*Dum2020q2 + PcpiBoundary )",

"Piret = Pgdp*EXP( Piret_Int + Piret_c3*TrendPiret )",

"Pxagr = Pxagr[1]*EXP( Pxagr_Int + Pxagr_c2*(LOG(Pxagr[1])-LOG(Fpagr[1]/Rusd[1])) + Pxagr_c3*((LOG(Fpagr)-LOG(Fpagr[1]))-(LOG(Rusd)-LOG(Rusd[1]))) + Pxagr_c4*((LOG(Fpagr[1])-LOG(Fpagr[2]))-(LOG(Rusd[1])-LOG(Rusd[2]))) + Pxagr_c5*Dum2009q1 + Pxagr_c6*Dum2023 )",

"Pmgs = Pmgs[1]*EXP( Pmgs_c1 + Pmgs_c2*(LOG(Pmgs[1]) - Pmgs_c3*LOG(Fpcpi[1]/RtwiNom[1]) - (1-Pmgs_c3)*LOG(Fpoil[1]/Rusd[1]) - Pmgs_c4*Trend) + Pmgs_c5*((LOG(Fpcpi)-LOG(Fpcpi[1]))-(LOG(RtwiNom)-LOG(RtwiNom[1]))) + Pmgs_c6*((LOG(Fpoil)-LOG(Fpoil[1]))-(LOG(Rusd)-LOG(Rusd[1]))) )",

"Rmort = Rmort[1] + Rmort_c1*(Rmort[1]-R90d[1]-Rmort_c2-Rmort_c3*Trend08[1]) + Rmort_c4*(R90d-R90d[1]) + Rmort_c5*(R90d[1]-R90d[2])",

"Peq = Peq[1]*EXP( Peq_Int + Peq_c2*(LOG(Ygdp[1])-LOG(Ygdp[2])) + Peq_c3*(LOG(Pcpi)-LOG(Pcpi[1])) + Peq_c4*(R90d-R90d[1]) + Peq_c5*(LOG(Fpcom)-LOG(Fpcom[1])) + Peq_c6*(LOG(Fpcom[1])-LOG(Fpcom[2])) )",

"Rtwi = Rtwi[1]*EXP( Rtwi_c1 + Rtwi_c2*(LOG(Rtwi[1]) + Rtwi_c3*LOG(Ptot[1]) + Rtwi_c4*Rdif10y[1] + Rtwi_c5*(Wfor[1]/YgdpNom[1])) + Rtwi_c6*(LOG(Ptot)-LOG(Ptot[1])) + Rtwi_c7*(Rdif10y-Rdif10y[1]) )",

"Rusd = Rusd[1]*EXP( Rusd_Int + Rusd_c2*(LOG(Rtwi)-LOG(Rtwi[1])) + Rusd_c3*((LOG(Fpcpi)-LOG(Fpcpi[1]))-(LOG(ABS(Pgdp))-LOG(Pgdp[1]))) )",

"Whh = Whh[1] + SavHh + Whh_c1*Whh[1] + Whh_c2*Whh[1]*(LOG(PhouseSa)-LOG(PhouseSa[1])) + Whh_c3*Whh[1]*(LOG(Peq)-LOG(Peq[1])) + Whh_c4*Whh[1]*(LOG(Rmort)-LOG(Rmort[1]))",

"Ygdw = Ygdw[1]*EXP( Ygdw_c1 + Ygdw_c2*(LOG(Ygdw[1]) - LOG(CprHpf[1]*Ppcd[1]) - Ygdw_c3*Trend) + Ygdw_c4*((LOG(CprHpf)-LOG(CprHpf[1]))+(LOG(Ppcd)-LOG(Ppcd[1]))) )",

"Lhrs = EXP( Lhrs_c1*(Lhrs_c2 + (LOG(Ygdp)-LOG(KTotal[1])) + Lhrs_c4*Trend + Lhrs_c5*(Ygdp-YgdpHpf)/YgdpHpf + Lhrs_c6*(LOG(Lwge)-LOG(ABS(Pgdp))) + Lhrs_c7*(LOG(Lwge[1])-LOG(Pgdp[1])) - (LOG(Lhrs[1])-LOG(KTotal[2]))) + Lhrs_c8*Dum2020q2 + Lhrs_c9*Dum2020q3 + LOG(Lhrs[1]) + LOG(KTotal[1]) - LOG(KTotal[2]) + LhrsBoundary )",

"PhouseSa = PhouseSa[1]*EXP( Phouse_c1 + Phouse_c2*((LOG(PhouseSa[1])-LOG(Pcpi[1])) - Phouse_c3*Trend - Phouse_c4*LOG(Lhh[1]/KDwell[1])) + Phouse_c5*(LOG(Pcpi)-LOG(Pcpi[1])) + Phouse_c6*(Rmort[1]-Rmort[2]) + Phouse_c7*(LOG(PhouseSa[1])-LOG(PhouseSa[2])) + Phouse_c8*(LOG(PhouseSa[2])-LOG(PhouseSa[3])) )",

"Pimin = Pimin[1]*EXP( Pimin_c1 + Pimin_c2*(LOG(Pimin[1]) - Pimin_c3*UlcDom[1] - (1-Pimin_c3)*LOG(Pmgs[1])) + Pimin_c4*(LOG(Pmgs)-LOG(Pmgs[1])) + Pimin_c6*(LOG(Pmgs[2])-LOG(Pmgs[3])) + Pimin_c7*(UlcDom-UlcDom[1]) + Pimin_c9*(UlcDom[2]-UlcDom[3]) + Pimin_c10*(UlcDom[3]-UlcDom[4]) + Pimin_c11*Dum2022 + Pimin_c12*Dum2023 )",

"Pinonmin = Pinonmin[1]*EXP( Pinonmin_c1 + Pinonmin_c2*(LOG(Pinonmin[1]) - Pinonmin_c3*UlcDom[1] - (1-Pinonmin_c3)*LOG(Pmgs[1])) + Pinonmin_c6*(LOG(Pmgs)-LOG(Pmgs[1])) + Pinonmin_c7*(UlcDom[1]-UlcDom[2]) + Pinonmin_c8*(LOG(Pmgs[1])-LOG(Pmgs[2])) + Pinonmin_c9*(LOG(Pmgs[2])-LOG(Pmgs[3])) + Pinonmin_c10*Dum2022 + Pinonmin_c11*Dum2023 )",

"Pgov = Pgov[1]*EXP( Pgov_c1 + Pgov_c2*(LOG(Pgov[1]) - Pgov_c3*UlcDom[1] - (1-Pgov_c3)*LOG(Pmgs[1])) + Pgov_c4*(UlcDom-UlcDom[1]) + Pgov_c5*(LOG(Pgov[1])-LOG(Pgov[2])) )",

"Pidwell = Pidwell[1]*EXP( Pidwell_c1 + Pidwell_c2*(LOG(Pidwell[1]) - Pidwell_c3*UlcDom[1] - (1-Pidwell_c3)*LOG(Pmgs[1]) - Pidwell_c4*Trend) + Pidwell_c5*Dum2000q3 + Pidwell_c6*(LOG(Pidwell[1])-LOG(Pidwell[2])) + Pidwell_c7*Dum2000q4 )",

"Pxsvc = Pxsvc[1]*EXP( Pxsvc_c1 + Pxsvc_c2*(LOG(Pxsvc[1]) - UlcExp[1] - Pxsvc_c4*Trend) + Pxsvc_c5*(UlcExp-UlcExp[1]) + Pxsvc_c6*(UlcExp[1]-UlcExp[2]) )",

"Tpit = Tpit[1]*EXP( Tpit_c1 + Tpit_c2*(LOG(Tpit[1])-LOG(Ynli[1])) + Tpit_c4*(LOG(ABS(Lur))-LOG(Lur[1])) + Tpit_c5*(LOG(Lur[1])-LOG(Lur[2])) + Tpit_c6*(LOG(Lwge[1])-LOG(Lwge[2])) + Tpit_c7*(LOG(Tpit[1])-LOG(Tpit[2])) + Tpit_c8*Dum2000q3 )",

"GovDebt = GovDebt[1] + GovDef + GovDebt_x*R10y[5]*GovDebt[1]",

"PcpiRent = PcpiRent[1]*EXP( PcpiRent_c1 + PcpiRent_c2*(LOG(PcpiRent[1])-LOG(PhouseHpf[1])-PcpiRent_c4*RmortRealHpf[1]) + PcpiRent_c5*Lnom/1000 + PcpiRent_c6*(LOG(Lwge)-LOG(Lwge[1])) + PcpiRent_c7*(LOG(Lwge[1])-LOG(Lwge[2])) + PcpiRent_c8*(LOG(PcpiRent[1])-LOG(PcpiRent[2])) + PcpiRentBoundary )",

"Inonmin = Inonmin[1]*EXP( Inonmin_Int + Inonmin_c2*(LOG(Inonmin[1])-LOG(Ygne[1])+0.6*LOG(CostCap[1])+(LOG(Pinonmin[1])-LOG(Pgne[1]))) + Inonmin_c5*(LOG(Ygne)-LOG(Ygne[1])) + Inonmin_c6*(LOG(Ygne[1])-LOG(Ygne[2])) + Inonmin_c7*(LOG(Ygne[2])-LOG(Ygne[3])) + Inonmin_c8*(LOG(Ygne[3])-LOG(Ygne[4])) + Inonmin_c9*(LOG(Inonmin[1])-LOG(Inonmin[2])) + Inonmin_c10*Dum2012q4 + Inonmin_c11*(LOG(Pinonmin)-LOG(Pinonmin[1])) )",

"Ynli = ( Ynli_Int + Ynli_rm*Rmort + Ynli_pe*EqYield + Ynli_pe1*EqYield[1] + Ynli_pe2*EqYield[2] + Ynli_pe3*EqYield[3] + Ynli_l_r*(Ynli[1]/(YgdpNom[1]-Ywss[1]-Ygdw[1])) ) * (YgdpNom - Ywss - Ygdw)",

"EqEarn = EqEarn[1]*EXP( EqEarn_c1 + EqEarn_c2*(LOG(EqEarn[1])-LOG(Ygoa[1]) - EqEarn_c3*LOG(Fpcom[1]/Pgdp[1]) - EqEarn_c4*Rusd[2] - EqEarn_c5*Trend) + EqEarn_c7*(LOG(Fpcom/Pgdp)-LOG(Fpcom[1]/Pgdp[1])) + EqEarn_c8*(Rusd[1]-Rusd[2]) + EqEarn_c9*(LOG(Ygoa)-LOG(Ygoa[1])) + EqEarn_c10*(LOG(Ygoa[1])-LOG(Ygoa[2])) + EqEarn_c11*(LOG(Ygoa[2])-LOG(Ygoa[3])) + EqEarn_c12*(LOG(Ygoa[3])-LOG(Ygoa[4])) + EqEarn_c13*(LOG(Ygoa[4])-LOG(Ygoa[5])) )",

"Tgst = Tgst[1]*EXP( Tgst_c1 + Tgst_c2*(LOG(Tgst[1])-LOG(CprNom[1]) - Tgst_c3*ShockGst - Tgst_c4*Trend) + Tgst_c5*(LOG(CprNom)-LOG(CprNom[1])) + Tgst_c6*(LOG(CprNom[1])-LOG(CprNom[2])) + Tgst_c7*(LOG(CprNom[2])-LOG(CprNom[3])) + Tgst_c8*(LOG(CprNom[3])-LOG(CprNom[4])) + Tgst_c9*(LOG(CprNom[4])-LOG(CprNom[5])) )",

"Xoth = Xoth[1]*EXP( Xoth_c1 + Xoth_c2*(LOG(Xoth[1])-LOG(Ygdp[1]) - Xoth_c3*(Pxoth[1]/Pgdp[1]) - Xoth_c4*Sb2001 - Xoth_c5*Sb2001*Trend) + Xoth_c6*((Pxoth/Pgdp)-(Pxoth[1]/Pgdp[1])) + Xoth_c7*(LOG(Ygdp)-LOG(Ygdp[1])) )",

"Pxmin = Pxmin[1]*EXP( Pxmin_c1 + Pxmin_c2*(LOG(Pxmin[1])-LOG(Fpcom[1]/Rusd[1])) + Pxmin_c3*(LOG(Fpcom)-LOG(Fpcom[1])) + Pxmin_c4*(LOG(Rusd)-LOG(Rusd[1])) )",

"Pxoth = Pxoth[1]*EXP( Pxoth_c1 + Pxoth_c2*(LOG(Pxoth[1]) - Pxoth_c3*UlcExp[1] - (1-Pxoth_c3)*LOG(Pmgs[1]) - Pxoth_c4*Trend[1]) + Pxoth_c5*(UlcExp-UlcExp[1]) + Pxoth_c6*(LOG(Pmgs)-LOG(Pmgs[1])) )",

"PconsExrent = PconsExrent[1]*EXP( PconsExrent_c1 + PconsExrent_c2*(LOG(PconsExrent[1]) - PconsExrent_c3*UlcDom[1] - (1-PconsExrent_c3)*LOG(Pmgs[1])) + PconsExrent_c4*(Lur-LurHpf)/Lur + PconsExrent_c5*(UlcDom-UlcDom[1]) + PconsExrent_c6*(LOG(Pmgs)-LOG(Pmgs[1])) + PconsExrent_c9*Dum2000q3 + PconsExrent_c10*(LOG(ABS(Lur))-LOG(Lur[1])) )",

"Ppcd = Ppcd[1]*EXP( Ppcd_c1*(LOG(PconsExrent)-LOG(PconsExrent[1])) + (1-Ppcd_c1)*(LOG(PconsRent)-LOG(PconsRent[1])) )",

"Xsvc = Xsvc[1]*EXP( Xsvc_c1 + Xsvc_c2*(LOG(Xsvc[1])-LOG(Ygdp[1]) - Xsvc_c3*(Pxsvc[1]/Pgdp[1]) - Xsvc_c4*LOG(IntStu[1])) + Xsvc_c5*((Pxsvc/Pgdp)-(Pxsvc[1]/Pgdp[1])) + Xsvc_c6*(LOG(Ygdp)-LOG(Ygdp[1])) + Xsvc_c7*(LOG(IntStu)-LOG(IntStu[1])) + Xsvc_c8*Dum2020q1 + Xsvc_c9*Dum2020q2 + Xsvc_c10*Dum2020q3 )",

"Mtot = Mtot[1]*EXP( Mtot_c1 + Mtot_c2*(LOG(Mtot[1]) - LOG(Ygne[1]) - Mtot_c3*(Pmgs[1]*100/Pgne[1])) + Mtot_c4*(LOG(Ygne)-LOG(Ygne[1])) + Mtot_c5*(LOG(Ygne[1])-LOG(Ygne[2])) + Mtot_c6*((Pmgs/Pgne)-(Pmgs[1]/Pgne[1])) )",

"R90d = R90d[1] + Rcash_c1*(RcashA + (Pcpi/Pcpi[4]-1) + Rcash_c2*(Lur-LurHpf) + Rcash_c3*D93*(Pcpi/Pcpi[4]-1-0.025) - R90d[1]) + Rcash_c4*(Lur-Lur[1]) + RcashBoundary",

"R10y = R10y[1] + R10y_Int + R10y_d_rat*(Rstar + InflExp - R10y[1]) + R10y_d_r90*(R90d - R10y[1])"
) }

# ---- identities -----------------------------------------------------------------

mdl_identities <- function() { c(
"GapAvh = (Lur - LurHpf)/Lur",
"Ivt = IvtFar + IvtNonfarm - IvtNonfarm[1]",
"Iotc = RatioIotc*Idwell",
"Xagr = ShareXagr*Ygdp",
"Xtot = Xmin + Xagr + Xoth + Xsvc + ResidXtot",
"CprNom = Ppcd*Cpr",
"CgovNom = Pgov*Cgov",
"Ttot = Tpit + Tcit + Tgst + Tprl + Toth",
"FiscalCovered = CgovNom + Pinonmin*(Igov + Ipubent) + Ytsf - Ttot",
"GovDef = GovDef[1] + FiscalFlowPassThrough*(FiscalCovered-FiscalCovered[1])/1000",
"IdwellNom = Pidwell*Idwell",
"IotcNom = Piret*Iotc",
"IminNom = Pimin*Imin",
"InonminNom = Pinonmin*Inonmin",
"YgovIvtNom = YgovIvtNom[1]*((Igov+Ipubent+Ivt)/(Igov[1]+Ipubent[1]+Ivt[1]))*(Pinonmin/Pinonmin[1])",
"XminNom = Pxmin*Xmin",
"XagrNom = Pxagr*Xagr",
"XothNom = Pxoth*Xoth",
"XsvcNom = (Pxsvc/100)*Xsvc",
"XtotNom = XminNom + XagrNom + XothNom + XsvcNom + ResidXtotNom",
"MtotNom = Pmgs*Mtot",
"YgdpNom = CprNom + CgovNom + IdwellNom + IotcNom + IminNom + InonminNom + YgovIvtNom + XtotNom - MtotNom + ResidYgdpNom",
"Ygdp = Cpr + Cgov + Idwell + Iotc + Imin + Inonmin + Igov + Ipubent + Ivt + Xtot - Mtot + ResidYgdp",
"Ygne = Cpr + Cgov + Idwell + Iotc + Imin + Inonmin + Igov + Ipubent + Ivt + ResidYgne",
"Pgne = 100*(CprNom + CgovNom + IdwellNom + IotcNom + IminNom + InonminNom + YgovIvtNom)/(Cpr + Cgov + Idwell + Iotc + Imin + Inonmin + Igov + Ipubent + Ivt) + ResidPgne",
"Pgdp = YgdpNom/Ygdp",
"Pxtot = XtotNom/Xtot",
"Ptot = 100*Pxtot/Pmgs",
"CconsRent = ShareCconsRent*Cpr",
"PconsRent = PconsRent[1]*(PcpiRent/PcpiRent[1])",
"CconsRentNom = PconsRent*CconsRent",
"LempMkt = TSLAG(LempMkt,1)*(Lhrs/TSLAG(Lhrs,1))*(TSLAG(LavhMkt,1)/LavhMkt)",
"Lemp = LempMkt + LempNonmkt",
"Lsup = Lpop15Plus*Lpar",
"Lune = Lsup - Lemp",
"Lur = Lune/Lsup",
"Lhh = RatioLhh*Lpop",
"Ywss = FactorYwss*Lwge*Lemp/1000",
"Yhdi = Yhdi[1]*((Ywss + Ynli + Ytsf - Tpit)/(Ywss[1] + Ynli[1] + Ytsf[1] - Tpit[1]))",
"Ygoa = FactorYgoa*(YgdpNom - Ywss - Ygdw)",
"SavHh = FactorSav*Yhdi",
"Wfor = RatioWfor*YgdpNom",
"EqYield = EqEarn/Peq",
"PeRatio = Peq/EqEarn",
"KMin = (1-RateKMinDep)*KMin[1] + Imin[1]",
"KNbiz = (1-RateKNbizDep)*KNbiz[1] + Inonmin[1]",
"KDwell = (1-RateKDwellDep)*KDwell[1] + Idwell[1]",
"KBiz = KMin + KNbiz",
"KTotal = KBiz + KDwell + LevelKOther",
"R90dReal = R90d - (Pcpi/Pcpi[4] - 1)",
"R10yReal = R10y - (Pcpi/Pcpi[4] - 1)",
"RmortReal = Rmort - (Pcpi/Pcpi[4] - 1)",
"PcpiExGst = PcpiExGst[1]*(Pcpi/Pcpi[1])",
"RmortRealExgst = Rmort - (PcpiExGst/PcpiExGst[4] - 1)",
"Fr10y = (3/5)*Fr10yUs + (1/6)*Fr10yJp + (1/12)*Fr10yUk + (3/20)*Fr10yDe",
"Fr10yReal = Fr10y - ((Fpcpi[2]/Fpcpi[6]-1) + (Fpcpi[6]/Fpcpi[10]-1))/2",
"Rdif10y = R10yReal - Fr10yReal",
"RtwiNom = Rtwi*Fpcpi[1]/PcpiExGst[1]",
"PhouseReal = PhouseSa/Pcpi",
"Rbiz = R90d + SpreadRbiz",
"RbizReal = (1-LevelTcorpRate)*Rbiz/(PconsExrent/PconsExrent[4])",
"KdepAllow = (LevelKdepRate*(1+R10y))*(R10y+LevelKdepRate)",
"CostCap = (RbizReal*LevelBizGear + EqYield*(1-LevelBizGear) + LevelKdepRate)*(1 - KdepAllow*LevelTcorpRate)",
"GovDem = Igov + Ipubent + Cgov",
"Pulc = Pulc[1]*(Lwge/Lwge[1])*(Ygdp/Ygdp[1])^(-1)*(Lemp/Lemp[1])",
"UlcDom = LOG(Pulc) + 0.002764*((1-BsC2)/BsC2)*Trend",
"UlcExp = LOG(Pulc) - 0.002764*Trend",
"RmortRealHpf = RmortRealHpf[1]",
"LparHpf = LparHpf[1]",
"PpcdHpf = PpcdHpf[1]*GrowthPpcdHpf",
"LurHpf = LurHpf[1]",
"InflExp = InflExp[1]"
) }

# ---- rendering ----------------------------------------------------------------

to_bimets_expr <- function(x, params) {
  x <- gsub("([A-Za-z][A-Za-z0-9.]*)\\[([0-9]+)\\]", "TSLAG(\\1,\\2)", x)
  for (k in names(params))
    x <- gsub(paste0("\\b", k, "\\b"), sprintf("%.17f", params[[k]]), x)
  # negative coefficients after a '+' produce '+-' or '+ -'; normalise
  repeat {
    y <- gsub("\\+\\s*-", "-", gsub("-\\s*\\+", "-", gsub("--", "+", x, fixed = TRUE)))
    if (identical(y, x)) break
    x <- y
  }
  x
}

# Simultaneous algorithms can temporarily cross zero even when the converged
# economic solution is positive. LOG(ABS(x)) is identical to LOG(x) at every
# admissible solution, but lets Newton move back after an intermediate
# overshoot. Parse balanced LOG() expressions so ratios are protected too.
guard_log_domains <- function(x) {
  cursor <- 1L
  repeat {
    hit <- regexpr("LOG\\(", substring(x, cursor), fixed = FALSE)
    if (hit[1] < 0) break
    start <- cursor + as.integer(hit[1]) - 1L
    open <- start + 3L
    depth <- 1L
    close <- open
    while (depth > 0L && close < nchar(x)) {
      close <- close + 1L
      token <- substr(x, close, close)
      if (token == "(") depth <- depth + 1L
      if (token == ")") depth <- depth - 1L
    }
    if (depth != 0L) stop("Unbalanced LOG() expression: ", x)
    argument <- substr(x, open + 1L, close - 1L)
    if (startsWith(trimws(argument), "ABS(")) {
      cursor <- close + 1L
    } else {
      x <- paste0(
        substr(x, 1L, open), "ABS(", argument, ")",
        substr(x, close, nchar(x))
      )
      cursor <- close + 6L
    }
  }
  x
}

mdl_equations_numeric <- function(model) {
  params <- mdl_parameters(model)
  eqs <- mdl_equations()
  out <- character(length(eqs))
  for (i in seq_along(eqs)) {
    out[i] <- guard_log_domains(to_bimets_expr(eqs[i], params))
  }
  apply_equation_shocks(out)
}

mdl_equation_lhs <- function(equations = mdl_equations()) {
  trimws(sub("\\s*=.*$", "", equations))
}

mdl_shock_contract <- function() {
  variables <- mdl_equation_lhs()
  additive <- c("LavhMkt", "Lpar", "Rmort", "Whh", "GovDebt", "R90d", "R10y")
  equation_shocks <- tibble::tibble(
    variable = variables,
    shock_variable = paste0("ShockEq", variables),
    target_variable = variables,
    scope = "equation",
    shock_type = dplyr::case_when(
      variables %in% additive ~ "additive",
      variables == "Ynli" ~ "ratio",
      TRUE ~ "log"
    )
  )
  exogenous <- mdl_exogenous_contract()$model_variable
  exogenous_additive <- c(
    "IvtFar", "Fr10yUs", "Fr10yJp", "Fr10yDe", "Fr10yUk"
  )
  exogenous_shocks <- tibble::tibble(
    variable = exogenous,
    shock_variable = paste0("ShockExo", exogenous),
    target_variable = exogenous,
    scope = "exogenous",
    shock_type = ifelse(exogenous %in% exogenous_additive, "additive", "log")
  )
  dplyr::bind_rows(equation_shocks, exogenous_shocks)
}

apply_equation_shocks <- function(equations) {
  contract <- dplyr::filter(mdl_shock_contract(), scope == "equation")
  vapply(equations, function(equation) {
    lhs <- mdl_equation_lhs(equation)
    rhs <- trimws(sub("^[^=]*=", "", equation))
    row <- contract[match(lhs, contract$variable), ]
    if (is.na(row$variable)) stop("No shock contract for equation ", lhs)
    shocked_rhs <- switch(
      row$shock_type,
      log = sprintf("(%s)*EXP(%s)", rhs, row$shock_variable),
      additive = sprintf("(%s) + %s", rhs, row$shock_variable),
      ratio = sprintf(
        "(%s) + %s*(YgdpNom - Ywss - Ygdw)",
        rhs, row$shock_variable
      )
    )
    paste(lhs, "=", shocked_rhs)
  }, "")
}

mdl_feedback_variables <- function() {
  c("Lur", "Cpr", "Ppcd", "Pgdp", "Ygdp", "Rtwi", "Ygne", "Inonmin")
}

damp_feedback_equations <- function(equations, weight = 0.1) {
  feedback <- mdl_feedback_variables()
  vapply(equations, function(equation) {
    lhs <- trimws(sub("\\s*=.*$", "", equation))
    if (!lhs %in% feedback) return(equation)
    rhs <- trimws(sub("^[^=]*=", "", equation))
    sprintf(
      "%s = %.17f*(%s) + %.17f*%s",
      lhs, weight, rhs, 1 - weight, lhs
    )
  }, "")
}

mdl_text <- function(model) {
  eqs <- mdl_equations_numeric(model)
  ids <- vapply(
    mdl_identities(),
    function(x) guard_log_domains(to_bimets_expr(x, mdl_parameters(model))),
    ""
  )
  # Under-relax only the variables in BIMETS' simultaneous feedback block.
  # The fixed point is unchanged: x = w*f(x) + (1-w)*x implies x = f(x).
  eqs <- damp_feedback_equations(eqs)
  ids <- damp_feedback_equations(ids)
  lhs_of <- function(x) trimws(gsub("\\s*=.*$", "", x))
  stopifnot(!any(duplicated(c(lhs_of(eqs), lhs_of(ids)))))
  paste(c("MODEL",
          unlist(lapply(seq_along(eqs), function(i)
            c(paste0("IDENTITY> ", lhs_of(eqs[i])), paste0("EQ> ", eqs[i])))),
          unlist(lapply(seq_along(ids), function(i)
            c(paste0("IDENTITY> ", lhs_of(ids[i])), paste0("EQ> ", ids[i])))),
          "END"),
        collapse = "\n")
}

# ---- coefficients ---------------------------------------------------------------

mdl_prefix <- c(Cpr = "Cpr", Idwell = "Idwell", Imin = "Imin", IvtNonfarm = "IvtNonfarm",
                Tcit = "Tcit", Tprl = "Tprl", Toth = "Toth", Ytsf = "Ytsf", Xmin = "Xmin",
                Lavh = "Lavh", LempNonmkt = "LempNonmkt", Lpar = "Lpar", Lwge = "Lwge",
                Pcpi = "Pcpi", Piret = "Piret", Pxagr = "Pxagr", Pmgs = "Pmgs",
                Rmort = "Rmort", Peq = "Peq", Rtwi = "Rtwi", Rusd = "Rusd", Whh = "Whh",
                Ygdw = "Ygdw", Lhrs = "Lhrs", Phouse = "Phouse", Pimin = "Pimin",
                Pinonmin = "Pinonmin", Pgov = "Pgov", Pidwell = "Pidwell",
                Pxsvc = "Pxsvc", Tpit = "Tpit", GovDebt = "GovDebt",
                PcpiRent = "PcpiRent", Inonmin = "Inonmin", Ynli = "Ynli",
                EqEarn = "EqEarn", Tgst = "Tgst", Xoth = "Xoth", Pxmin = "Pxmin",
                Pxoth = "Pxoth", PconsExrent = "PconsExrent", Ppcd = "Ppcd", Xsvc = "Xsvc",
                Mtot = "Mtot", Rcash = "Rcash", R10y = "R10y")

mdl_parameters <- function(model) {
  params <- list()
  for (nm in names(model$fits)) {
    co <- if (inherits(model$fits[[nm]], c("lm", "nls")))
      stats::coef(model$fits[[nm]]) else model$fits[[nm]]$par
    pre <- mdl_prefix[[nm]]
    for (k in names(co)) {
      key <- if (k == "(Intercept)") "Int" else k
      params[[paste0(pre, "_", key)]] <- as.numeric(co[[k]])
    }
  }
  for (k in names(RCASH_IMPOSED)) params[[paste0("Rcash_", k)]] <- RCASH_IMPOSED[[k]]
  params
}

# ---- auxiliary regressors from the estimation frames ----------------------------

aux_regressors <- function(model, data) {
  n <- nrow(data)
  aux <- data.frame(CprDum = rep(0, n), LavhDum = rep(0, n),
                    LavhDum1 = rep(0, n), RcashA = NA_real_,
                    RstarFiltered = NA_real_)
  cf <- model$fits$Rcash$par
  cf[names(RCASH_IMPOSED)] <- RCASH_IMPOSED
  Q <- exp(2 * cf[["log_sig_state"]]); H <- exp(2 * cf[["log_sig_obs"]])
  rc <- data %>%
    mutate(inf = Pcpi / lag(Pcpi, 4) - 1, dr = R90d - lag(R90d),
           gap = Lur - LurHpf, dlur = Lur - lag(Lur), r_lag = lag(R90d)) %>%
    filter(!is.na(dr), !is.na(inf), !is.na(gap), !is.na(dlur), date >= "1976-03-01")
  a <- 0; P <- 100
  idx <- match(rc$date, data$date)
  for (k in seq_len(nrow(rc))) {
    aux$RcashA[idx[k]] <- a
    P_pred <- P + Q
    yhat <- cf[["c1"]] * (a + rc$inf[k] + cf[["c2"]] * rc$gap[k] +
             cf[["c3"]] * rc$d93[k] * (rc$inf[k] - 0.025) - rc$r_lag[k]) +
             cf[["c4"]] * rc$dlur[k]
    F <- cf[["c1"]]^2 * P_pred + H
    v <- rc$dr[k] - yhat
    K <- cf[["c1"]] * P_pred / F
    a <- a + K * v
    P <- P_pred * H / F
    aux$RstarFiltered[idx[k]] <- a
  }
  aux
}

# ---- forecast contracts ---------------------------------------------------------

# The residual-calibration inputs that must be observed at the conditioning
# quarter. The workbook's data end is ragged after an update (quarterly
# national accounts, monthly rates and skipped series end at different
# quarters), so the model conditions at the last quarter where all of these
# are finite - the original design's "later rows are for comparison only"
# rule, generalised.
CONDITIONING_INPUTS <- c(
  "Pcpi", "Ppcd", "PcpiRent", "PhouseHpf", "RmortRealHpf", "Lnom", "Lwge",
  "R90d", "Lur", "LurHpf", "d93", "Lhrs", "KTotal", "Ygdp", "YgdpHpf",
  "Pgdp", "trend"
)

forecast_origin <- function(data) {
  dates <- as.Date(data$date)
  if (anyNA(dates) || anyDuplicated(dates) > 0L) {
    stop("Model data dates must be complete and unique")
  }
  if (!all(lubridate::month(dates) %in% c(3, 6, 9, 12)) ||
      any(lubridate::mday(dates) != 1L)) {
    stop("Model data dates must be quarter-aligned")
  }
  quarters <- lubridate::year(dates) * 4L + lubridate::quarter(dates)
  if (!all(diff(quarters) == 1L)) {
    stop("Model data dates must be consecutive quarters")
  }
  missing <- setdiff(CONDITIONING_INPUTS, names(data))
  if (length(missing)) {
    stop("Model data is missing conditioning inputs: ",
         paste(missing, collapse = ", "))
  }
  complete <- Reduce(`&`, lapply(data[CONDITIONING_INPUTS],
                                 function(x) is.finite(as.numeric(x))))
  if (!any(complete)) stop("No quarter has complete conditioning inputs")
  conditioning <- max(dates[complete])
  seq(conditioning, by = "quarter", length.out = 2L)[2L]
}

mdl_exogenous_contract <- function() {
  tibble::tribble(
    ~forecast_column,       ~model_variable, ~units,                                      ~extension_policy,
    "Lpop",                 "Lpop",          "thousand persons",                         "official annual components; quarterly interpolation; two-quarter terminal extension",
    "Lpop15Plus",           "Lpop15Plus",    "thousand persons aged 15 and over",        "official projected 15-plus share applied to Lpop; two-quarter terminal share hold",
    "Cgov",                 "Cgov",          "quarterly chain-volume $m",                 "apply official aggregate public-demand growth; constant real per capita after source horizon",
    "Igov",                 "Igov",          "quarterly chain-volume $m",                 "apply official aggregate public-demand growth; constant real per capita after source horizon",
    "Ipubent",              "Ipubent",       "quarterly chain-volume $m",                 "apply official aggregate public-demand growth; constant real per capita after source horizon",
    "IvtFar",               "IvtFar",        "quarterly chain-volume $m",                 "zero neutral closure",
    "Lnom",                 "Lnom",          "thousand persons per quarter",              "official annual total divided by four; two-quarter terminal carry",
    "IntStu",               "IntStu",        "new international student enrolments",      "apply official current-data trend below policy ceiling; hold",
    "Fpcpi",                "Fpcpi",         "index",                                     "compound official inflation forecast; two-percent terminal inflation",
    "Fpoil",                "Fpoil",         "USD price",                                 "interpolate official annual forecast; hold terminal level",
    "Fpcom",                "Fpcom",         "real commodity-price index",                "rebase and deflate official forecast; hold terminal real level",
    "Fpagr",                "Fpagr",         "USD agricultural-price index",              "rebase official forecast; hold terminal level",
    "FcGdp",                "FcGdp",         "China real GDP",                            "official medium- and long-run growth; quarterly interpolation",
    "FcPpp",                "FcPpp",         "China PPP conversion rate",                 "rebase official forecast; hold terminal level",
    "Fr10yUs",              "Fr10yUs",       "decimal annual rate",                       "official annual forecast; hold terminal rate",
    "Fr10yJp",              "Fr10yJp",       "decimal annual rate",                       "official annual forecast; hold terminal rate",
    "Fr10yDe",              "Fr10yDe",       "decimal annual rate",                       "official annual forecast; hold terminal rate",
    "Fr10yUk",              "Fr10yUk",       "decimal annual rate",                       "official annual forecast; hold terminal rate"
  )
}

mdl_realtime_hpf_contract <- function() {
  tibble::tribble(
    ~model_variable, ~source_variable,
    "YgdpHpf",       "Ygdp",
    "CprHpf",        "Cpr",
    "PhouseHpf",     "PhouseSa"
  )
}

# ---- database -------------------------------------------------------------------

build_ts_database <- function(data, exo, model, shocks, origin = forecast_origin(data),
                              horizon = as.Date("2036-12-01"),
                              residuals_path = "outputs/residuals.csv",
                              carry_forward = TRUE, observed = NULL) {
  # The full data set is used for estimation, but forecast conditioning must
  # stop at 2024Q4. Later actual outcomes are retained only for comparison and
  # must not enter lags, residual calibrations, trends, or solver seeds.
  data <- data[as.Date(data$date) < as.Date(origin), , drop = FALSE]
  expected_last <- seq(as.Date(origin), by = "-3 months", length.out = 2)[2]
  if (max(as.Date(data$date)) != expected_last) {
    stop("Forecast history must end one quarter before the forecast origin")
  }
  dates <- seq(min(data$date), horizon, by = "quarter")
  n <- length(dates); nh <- nrow(data)
  start <- c(lubridate::year(dates[1]), lubridate::quarter(dates[1]))
  mk <- function(x) {
    if (length(x) < n) {
      lastv <- tail(x[!is.na(x)], 1)
      x <- c(x, rep(lastv, n - length(x)))
    }
    # carry observations through internal NAs (history only affects lags)
    i <- which(!is.na(x))
    if (length(i)) {
      x[seq_len(i[1] - 1)] <- x[i[1]]
      for (k in seq_along(i)[-1]) {
        lo <- i[k - 1] + 1; hi <- i[k] - 1
        if (lo <= hi) x[lo:hi] <- x[i[k - 1]]
      }
      lo <- i[length(i)] + 1
      if (lo <= length(x)) x[lo:length(x)] <- x[i[length(i)]]
    }
    ts(x, start = start, frequency = 4)
  }
  db <- list()
  for (v in setdiff(names(data), "date")) db[[v]] <- mk(as.numeric(data[[v]]))
  db_const_ygovivt <- function(d) {
    as.numeric(d$YgdpNom + d$MtotNom - d$CprNom - d$CgovNom - d$IdwellNom -
      d$IotcNom - d$IminNom - d$InonminNom - d$XtotNom)
  }

  # history for model-only series (defined by identities in the forecast)
  db$GapAvh <- mk(as.numeric(data$Lur - data$LurHpf) / as.numeric(data$Lur))
  db$FiscalCovered <- mk(as.numeric(data$CgovNom + data$Pinonmin *
    (data$Igov + data$Ipubent) + data$Ytsf - data$Ttot))
  db$XsvcNom <- mk(as.numeric(data$XtotNom - data$XminNom - data$XagrNom - data$XothNom))
  db$YgovIvtNom <- mk(as.numeric(data$YgdpNom + data$MtotNom - data$CprNom -
    data$CgovNom - data$IdwellNom - data$IotcNom - data$IminNom -
    data$InonminNom - data$XtotNom))
  # Refilter the latent neutral rate using only observations dated before the
  # forecast origin. model$data$Rstar is RTS-smoothed over the full estimation
  # vintage and would otherwise leak the 2025-26 outcomes into 2025Q1.
  aux <- aux_regressors(model, data)
  db$Rstar <- mk(aux$RstarFiltered)
  rbiz_real <- as.numeric((1 - data$TcorpRate) * data$Rbiz /
    (data$PconsExrent / dplyr::lag(data$PconsExrent, 4)))
  kdep_allow <- as.numeric((data$KdepRate * (1 + data$R10y)) * (data$R10y + data$KdepRate))
  cost_cap <- as.numeric((rbiz_real * data$BizGear + data$EqYield *
    (1 - data$BizGear) + data$KdepRate) * (1 - kdep_allow * data$TcorpRate))
  db$RbizReal <- mk(rbiz_real)
  db$KdepAllow <- mk(kdep_allow)
  db$CostCap <- mk(cost_cap)

  # Explicit scenario paths. Historical observations are never overwritten;
  # parse_exogenous_csv() guarantees complete forecast-quarter coverage.
  contract <- mdl_exogenous_contract()
  iexo <- match(exo$date, dates)
  fill_path <- function(x, variable) {
    observed <- which(!is.na(x))
    if (!length(observed)) stop("No actual or scenario value for ", variable)
    if (observed[1] > 1) x[seq_len(observed[1] - 1)] <- x[observed[1]]
    if (observed[1] < length(x)) {
      for (i in seq.int(observed[1] + 1, length(x))) {
        if (is.na(x[i])) x[i] <- x[i - 1]
      }
    }
    x
  }
  for (i in seq_len(nrow(contract))) {
    source_name <- contract$forecast_column[i]
    target_name <- contract$model_variable[i]
    x <- rep(NA_real_, n)
    historical_values <- if (target_name == "Lpop15Plus") {
      as.numeric(data$Lsup) / as.numeric(data$Lpar)
    } else {
      as.numeric(data[[target_name]])
    }
    x[seq_len(nh)] <- historical_values
    vals <- as.numeric(exo[[source_name]])
    forecast_cells <- exo$date >= origin & exo$date <= horizon
    if (any(is.na(vals[forecast_cells]))) {
      stop("Incomplete forecast-quarter path for ", source_name)
    }
    use <- !is.na(vals) & exo$date >= origin
    x[iexo[use]] <- vals[use]
    db[[target_name]] <- ts(fill_path(x, target_name), start = start, frequency = 4)
  }

  # Equation shocks are zero in history and use equation-native units in the
  # forecast: log innovations, additive level/rate innovations, or a ratio
  # innovation for Ynli.
  shock_contract <- mdl_shock_contract()
  ishock <- match(shocks$date, dates)
  for (i in seq_len(nrow(shock_contract))) {
    x <- rep(0, n)
    use <- shocks$date >= origin & shocks$date <= horizon
    x[ishock[use]] <- as.numeric(shocks[[shock_contract$variable[i]]][use])
    db[[shock_contract$shock_variable[i]]] <- ts(x, start = start, frequency = 4)
  }
  exogenous_shocks <- dplyr::filter(shock_contract, scope == "exogenous")
  forecast_cells <- dates >= origin & dates <= horizon
  for (i in seq_len(nrow(exogenous_shocks))) {
    target <- exogenous_shocks$target_variable[i]
    shock <- as.numeric(db[[exogenous_shocks$shock_variable[i]]])
    values <- as.numeric(db[[target]])
    values[forecast_cells] <- if (exogenous_shocks$shock_type[i] == "log") {
      values[forecast_cells] * exp(shock[forecast_cells])
    } else {
      values[forecast_cells] + shock[forecast_cells]
    }
    db[[target]] <- ts(values, start = start, frequency = 4)
  }

  # deterministic terms
  q <- dates
  det <- list(
    Trend = seq_len(n) - 1,
    TrendIvt = pmin(seq_len(n) - 1, nh - 1),
    TrendPiret = seq_len(n) - 1 + 8,
    Trend98 = cumsum(q >= as.Date("1998-03-01")),
    Trend01 = cumsum(q >= as.Date("2001-03-01")),
    Trend08 = cumsum(q >= as.Date("2008-03-01")),
    D93 = as.numeric(q >= as.Date("1993-03-01")),
    Q3ind = as.numeric(lubridate::month(q) == 9),
    ShockGst = local({
      x <- as.numeric(data$ShockGst)
      x[is.na(x)] <- 0
      c(x, rep(0, n - nh))
    }),
    Sb2001 = as.numeric(q >= as.Date("2002-03-01")),
    Dum2022 = as.numeric(lubridate::year(q) == 2022),
    Dum2023 = as.numeric(lubridate::year(q) == 2023))
  ev <- c(Dum1975q3 = "1975-09-01", Dum1976q4 = "1976-12-01", Dum2009q1 = "2009-03-01",
          Dum2020q1 = "2020-03-01", Dum2020q2 = "2020-06-01", Dum2020q3 = "2020-09-01",
          Dum2020q4 = "2020-12-01", Dum2021q1 = "2021-03-01", Dum2000q3 = "2000-09-01",
          Dum2000q4 = "2000-12-01", Dum2012q4 = "2012-12-01", Dum2022q1 = "2022-03-01")
  for (nm in names(ev)) det[[nm]] <- as.numeric(q == as.Date(ev[[nm]]))
  for (nm in names(det)) db[[nm]] <- ts(det[[nm]], start = start, frequency = 4)

  # Historical tracking runs may supply observed values for the data-driven
  # equation inputs that the production forecast holds at zero or their last
  # historical value (the COVID tax and transfer corrections ShockGst and
  # DumTsfTot). Without this, a simulation window over 2020-2022 would miss
  # the corrections the equations were estimated with.
  if (!is.null(observed)) {
    for (nm in intersect(c("ShockGst", "DumTsfTot"), names(observed))) {
      idx <- match(as.Date(observed$date), dates)
      cells <- !is.na(idx) & idx > nh & !is.na(observed[[nm]])
      db[[nm]][idx[cells]] <- as.numeric(observed[[nm]][cells])
    }
  }

  # auxiliary regressors (zero in forecast)
  for (nm in c("CprDum", "LavhDum", "LavhDum1"))
    db[[nm]] <- ts(c(replace(aux[[nm]], is.na(aux[[nm]]), 0), rep(0, n - nh)),
                   start = start, frequency = 4)
  # Historical RcashA is the prior state used by each observed-rate equation.
  # The first forecast prior is instead the posterior after assimilating the
  # final conditioning observation (2024Q4), propagated by the random walk.
  forecast_state <- tail(aux$RstarFiltered[is.finite(aux$RstarFiltered)], 1)
  ra <- c(aux$RcashA, rep(forecast_state, n - nh))
  first_state <- aux$RcashA[which(is.finite(aux$RcashA))[1]]
  missing_history <- seq_len(nh)[!is.finite(ra[seq_len(nh)])]
  ra[missing_history] <- first_state
  db$RcashA <- ts(ra, start = start, frequency = 4)
  db$BsC2 <- ts(rep(model$bs_c2, n), start = start, frequency = 4)

  # Equation residuals are calculated by the standalone R/calculate_residuals.R
  # script and read from its exported CSV. With carry_forward = TRUE each final
  # observed residual enters the first forecast quarter and fades geometrically
  # at its recorded persistence; with carry_forward = FALSE the residuals are
  # set to zero and every boundary path is identically zero.
  residual_frames <- read_residuals_csv(residuals_path)
  conditioning_date <- dates[nh]
  if (carry_forward &&
      any(residual_frames$conditioning_date != conditioning_date)) {
    stale <- unique(format(residual_frames$conditioning_date[
      residual_frames$conditioning_date != conditioning_date
    ]))
    stop(
      "Exported residuals were conditioned on ", paste(stale, collapse = ", "),
      " but the simulation conditions on ", format(conditioning_date),
      ". Re-run Rscript R/calculate_residuals.R or run_model.R."
    )
  }
  boundary_path <- function(residual, persistence) {
    if (!carry_forward) residual <- 0
    ts(c(rep(0, nh), residual * persistence^seq.int(0, n - nh - 1L)),
       start = start, frequency = 4)
  }
  for (k in seq_len(nrow(residual_frames))) {
    db[[residual_frames$boundary_variable[[k]]]] <- boundary_path(
      residual_frames$residual[[k]], residual_frames$persistence[[k]]
    )
  }

  # carried residuals / factors / held parameters (constant series).
  # Each is computed at the last row where ALL its inputs are observed, so
  # series with different end dates align properly.
  last_common <- function(...) {
    m <- Reduce(`&`, lapply(list(...), function(v) !is.na(v)))
    max(which(m))
  }
  v <- function(nm) as.numeric(data[[nm]])
  ratio_at <- function(num_v, den_v) {
    j <- last_common(num_v, den_v)
    mean(tail(num_v[seq_len(j)], 8)) / mean(tail(den_v[seq_len(j)], 8))
  }
  ywss_f <- ratio_at(v("Ywss"), v("Lwge") * v("Lemp") / 1000)
  ygoa_f <- ratio_at(v("Ygoa"), v("YgdpNom") - v("Ywss") - v("Ygdw"))
  sav_f <- ratio_at(v("SavHh"), v("Yhdi"))
  xagr_s <- ratio_at(v("Xagr"), v("Ygdp"))
  ccr_s <- ratio_at(v("CconsRent"), v("Cpr"))
  iotc_r <- ratio_at(v("Iotc"), v("Idwell"))
  i <- last_common(v("Xtot"), v("Xmin"), v("Xagr"), v("Xoth"), v("Xsvc"))
  resid_xtot <- v("Xtot")[i] - (v("Xmin")[i] + v("Xagr")[i] + v("Xoth")[i] + v("Xsvc")[i])
  xsvc_nom <- (v("Pxsvc") / 100) * v("Xsvc")
  i <- last_common(v("XtotNom"), v("XminNom"), v("XagrNom"), v("XothNom"), xsvc_nom)
  resid_xtotnom <- v("XtotNom")[i] - (v("XminNom")[i] + v("XagrNom")[i] +
    v("XothNom")[i] + xsvc_nom[i])
  sumexp <- v("Cpr") + v("Cgov") + v("Idwell") + v("Iotc") + v("Imin") + v("Inonmin") +
    v("Igov") + v("Ipubent") + v("Ivt") + v("Xtot") - v("Mtot")
  sumgne <- v("Cpr") + v("Cgov") + v("Idwell") + v("Iotc") + v("Imin") + v("Inonmin") +
    v("Igov") + v("Ipubent") + v("Ivt")
  i <- last_common(v("Ygdp"), sumexp); resid_ygdp <- v("Ygdp")[i] - sumexp[i]
  i <- last_common(v("Ygne"), sumgne); resid_ygne <- v("Ygne")[i] - sumgne[i]
  gne_nom <- v("CprNom") + v("CgovNom") + v("IdwellNom") + v("IotcNom") +
    v("IminNom") + v("InonminNom") + db_const_ygovivt(data)
  sumnom <- gne_nom + v("XtotNom") - v("MtotNom")
  i <- last_common(v("YgdpNom"), sumnom); resid_ygdpnom <- v("YgdpNom")[i] - sumnom[i]
  i <- last_common(v("Pgne"), gne_nom, sumgne)
  resid_pgne <- v("Pgne")[i] - 100 * gne_nom[i] / sumgne[i]
  i <- last_common(v("Wfor"), v("YgdpNom")); ratio_wfor <- v("Wfor")[i] / v("YgdpNom")[i]
  i <- last_common(v("Lhh"), v("Lpop")); ratio_lhh <- v("Lhh")[i] / v("Lpop")[i]
  fiscal_covered <- v("CgovNom") + v("Pinonmin") * (v("Igov") + v("Ipubent")) +
    v("Ytsf") - v("Ttot")
  fiscal_sample <- data$date >= as.Date("2004-03-01") &
    is.finite(v("GovDef")) & is.finite(fiscal_covered)
  deficit_change <- diff(v("GovDef")[fiscal_sample])
  covered_change <- diff(fiscal_covered[fiscal_sample] / 1000)
  fiscal_pass_through <- sum(deficit_change * covered_change) / sum(covered_change^2)
  mean8 <- function(nm) { x <- v(nm); mean(tail(x[!is.na(x)], 8)) }
  hold_last <- function(nm) { x <- v(nm); tail(x[!is.na(x)], 1) }
  trend_growth <- function(nm) {
    x <- v(nm)
    x <- x[is.finite(x) & x > 0]
    exp(mean(tail(diff(log(x)), 8)))
  }
  rbiz_spread <- {
    x <- v("Rbiz") - v("R90d")
    mean(tail(x[is.finite(x)], 8))
  }
  const <- c(
    ResidXtot = resid_xtot,
    ResidXtotNom = resid_xtotnom,
    ResidYgdpNom = resid_ygdpnom,
    ResidYgdp = resid_ygdp,
    ResidYgne = resid_ygne,
    ResidPgne = resid_pgne,
    FactorYwss = ywss_f,
    FactorYgoa = ygoa_f,
    FactorSav = sav_f,
    ShareXagr = xagr_s,
    ShareCconsRent = ccr_s,
    RatioIotc = iotc_r,
    RatioWfor = ratio_wfor,
    RatioLhh = ratio_lhh,
    FiscalFlowPassThrough = fiscal_pass_through,
    GrowthPpcdHpf = trend_growth("PpcdHpf"),
    RateKMinDep = mean8("KMinDepRate"),
    RateKNbizDep = mean8("KNbizDepRate"),
    RateKDwellDep = mean8("KDwellDepRate"),
    LevelKOther = hold_last("KOther"),
    LevelBizGear = hold_last("BizGear"),
    LevelTcorpRate = hold_last("TcorpRate"),
    LevelKdepRate = hold_last("KdepRate"),
    SpreadRbiz = rbiz_spread)
  for (nm in names(const))
    db[[nm]] <- ts(rep(as.numeric(const[[nm]]), n), start = start, frequency = 4)

  db
}

# ---- exogenous csv --------------------------------------------------------------

parse_exogenous_csv <- function(path = "data-raw/exogenous_forecast.csv",
                                origin = NULL,
                                horizon = as.Date("2036-12-01")) {
  raw <- readr::read_csv(path, show_col_types = FALSE,
                         col_types = readr::cols(.default = "character"))
  required <- c("date", mdl_exogenous_contract()$forecast_column)
  missing_columns <- setdiff(required, names(raw))
  extra_columns <- setdiff(names(raw), required)
  if (length(missing_columns))
    stop("Missing exogenous forecast columns: ", paste(missing_columns, collapse = ", "))
  if (length(extra_columns))
    stop("Unexpected exogenous forecast columns: ", paste(extra_columns, collapse = ", "))
  d <- raw[[1]]
  serial <- grepl("^[0-9]+$", d)
  iso <- grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", d)
  slash <- grepl("^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$", d)
  dates <- rep(as.Date(NA), length(d))
  dates[serial] <- as.Date(as.numeric(d[serial]), origin = "1899-12-30")
  dates[iso] <- as.Date(d[iso], "%Y-%m-%d")
  dates[slash] <- as.Date(d[slash], "%d/%m/%Y")
  if (anyNA(dates)) stop("Unparseable dates in exogenous forecast CSV")
  raw$date <- dates
  raw <- raw[order(raw$date), ]
  if (anyDuplicated(raw$date)) stop("Duplicate dates in exogenous forecast CSV")
  q <- lubridate::year(raw$date) * 4 + lubridate::quarter(raw$date)
  if (!all(diff(q) == 1)) stop("Exogenous forecast dates must be consecutive quarters")
  if (!is.null(origin) && min(raw$date) > origin)
    stop("Exogenous forecast starts after the model forecast origin")
  if (max(raw$date) < horizon)
    stop("Exogenous forecast ends before the requested horizon")
  for (nm in setdiff(required, "date")) {
    populated <- !is.na(raw[[nm]]) & nzchar(trimws(raw[[nm]]))
    parsed <- suppressWarnings(as.numeric(raw[[nm]][populated]))
    if (anyNA(parsed)) stop("Non-numeric values in exogenous column ", nm)
  }
  raw <- raw[raw$date <= horizon, ]
  if (!is.null(origin)) {
    forecast_rows <- raw$date >= origin & raw$date <= horizon
    for (nm in setdiff(required, "date")) {
      missing_forecast <- forecast_rows &
        (is.na(raw[[nm]]) | !nzchar(trimws(raw[[nm]])))
      if (any(missing_forecast)) {
        stop(
          "Missing forecast-quarter values in exogenous column ", nm,
          ": ", paste(format(raw$date[missing_forecast]), collapse = ", ")
        )
      }
    }
  }
  raw
}

# The all-zero baseline shocks file must carry exactly one row per forecast
# quarter. When the forecast origin moves (an updated Data.xlsx), realign the
# baseline automatically - but only while it is provably the all-zero
# baseline; a file with scenario values is the user's and must never be
# rewritten.
align_baseline_shocks <- function(path, origin, horizon) {
  shocks <- readr::read_csv(path, show_col_types = FALSE,
                            col_types = readr::cols(.default = "character"))
  expected <- format(seq(as.Date(origin), as.Date(horizon), by = "quarter"))
  if (identical(as.character(shocks$date), expected)) return(invisible())
  values <- as.matrix(shocks[, setdiff(names(shocks), "date"), drop = FALSE])
  if (any(values != "0" & !is.na(values) & nzchar(values))) {
    stop("The baseline shocks file does not match the forecast window (",
         format(origin), " to ", format(horizon),
         ") and contains non-zero values. Rebuild it before running.")
  }
  aligned <- cbind(
    data.frame(date = expected),
    matrix(0, nrow = length(expected),
           ncol = ncol(shocks) - 1,
           dimnames = list(NULL, setdiff(names(shocks), "date")))
  )
  names(aligned) <- names(shocks)
  readr::write_csv(aligned, path, na = "")
  message("Baseline shocks realigned to the forecast window: ",
          length(expected), " quarters from ", format(origin))
  invisible()
}

parse_shocks_csv <- function(path = "data-raw/shocks.csv",
                             origin,
                             horizon = as.Date("2036-12-01")) {
  raw <- readr::read_csv(
    path,
    show_col_types = FALSE,
    col_types = readr::cols(.default = "character")
  )
  required <- c("date", mdl_shock_contract()$variable)
  missing_columns <- setdiff(required, names(raw))
  extra_columns <- setdiff(names(raw), required)
  if (length(missing_columns))
    stop("Missing shock columns: ", paste(missing_columns, collapse = ", "))
  if (length(extra_columns))
    stop("Unexpected shock columns: ", paste(extra_columns, collapse = ", "))
  raw <- raw[, required]

  dates <- suppressWarnings(as.Date(raw$date, "%Y-%m-%d"))
  if (anyNA(dates)) stop("Shock dates must use YYYY-MM-DD format")
  if (anyDuplicated(dates)) stop("Duplicate dates in shocks CSV")
  raw$date <- dates
  raw <- raw[raw$date <= as.Date(horizon), ]
  raw <- raw[order(raw$date), ]
  expected_dates <- seq(as.Date(origin), as.Date(horizon), by = "quarter")
  if (!identical(as.Date(raw$date), expected_dates)) {
    stop("Shocks CSV must contain exactly one row for every forecast quarter")
  }
  for (nm in setdiff(required, "date")) {
    values <- suppressWarnings(as.numeric(raw[[nm]]))
    if (any(!is.finite(values))) stop("Non-numeric or missing values in shock column ", nm)
    raw[[nm]] <- values
  }
  raw
}

# ---- simulation -----------------------------------------------------------------

run_bimets_forecast <- function(data, model, exo, shocks, origin = forecast_origin(data),
                                horizon = as.Date("2036-12-01"),
                                residuals_path = "outputs/residuals.csv",
                                carry_forward = TRUE, observed = NULL,
                                convergence = 1e-6, iterlimit = 1000,
                                hpf_convergence = 1e-5, hpf_iterlimit = 12,
                                show_progress = TRUE) {
  started_at <- Sys.time()
  if (show_progress) message("BIMETS: loading model")
  mdl <- LOAD_MODEL(modelText = mdl_text(model), quietly = TRUE)
  if (show_progress) message("BIMETS: building simulation database")
  db <- build_ts_database(data, exo, model, shocks, origin, horizon,
                          residuals_path, carry_forward, observed)
  forecast_dates <- seq(as.Date(origin), as.Date(horizon), by = "quarter")
  all_dates <- seq(min(as.Date(data$date)), as.Date(horizon), by = "quarter")
  contract <- mdl_realtime_hpf_contract()
  date_index <- function(date) match(as.Date(date), all_dates)
  series_at <- function(container, variable) {
    hit <- which(tolower(names(container)) == tolower(variable))
    if (length(hit) != 1L) stop("Expected one model series for ", variable)
    container[[hit]]
  }
  endpoint_weights <- function(n, lambda = 1600) {
    D <- diff(diag(n), differences = 2)
    endpoint <- numeric(n)
    endpoint[n] <- 1
    as.numeric(solve(diag(n) + lambda * crossprod(D), endpoint))
  }
  copy_period <- function(database, simulation, i) {
    for (variable in names(simulation)) {
      hit <- which(tolower(names(database)) == tolower(variable))
      if (length(hit) == 1L) database[[hit]][i] <- as.numeric(simulation[[variable]])[[1]]
    }
    database
  }

  result <- NULL
  for (date in forecast_dates) {
    date <- as.Date(date, origin = "1970-01-01")
    i <- date_index(date)
    weights <- endpoint_weights(i)
    operators <- lapply(seq_len(nrow(contract)), function(j) {
      values <- as.numeric(db[[contract$source_variable[j]]])[seq_len(i)]
      if (any(!is.finite(values))) stop("Non-finite HP-filter input")
      c(intercept = sum(weights[-i] * values[-i]), slope = weights[i])
    })
    for (iteration in seq_len(hpf_iterlimit)) {
      mdl <- LOAD_MODEL_DATA(model = mdl, modelData = db, quietly = TRUE)
      result <- SIMULATE(
        mdl,
        TSRANGE = c(lubridate::year(date), lubridate::quarter(date),
                    lubridate::year(date), lubridate::quarter(date)),
        simType = "DYNAMIC", simAlgo = "GAUSS-SEIDEL",
        simConvergence = convergence, simIterLimit = iterlimit, quietly = TRUE
      )
      candidate <- vapply(seq_len(nrow(contract)), function(j) {
        value <- as.numeric(series_at(result$simulation, contract$source_variable[j]))[[1]]
        operators[[j]][["intercept"]] + operators[[j]][["slope"]] * value
      }, numeric(1))
      previous <- vapply(contract$model_variable, function(variable) {
        as.numeric(db[[variable]])[[i]]
      }, numeric(1))
      error <- max(abs(candidate - previous) / pmax(1, abs(candidate), abs(previous)))
      for (j in seq_len(nrow(contract))) db[[contract$model_variable[j]]][i] <- candidate[j]
      if (error < hpf_convergence) break
      if (iteration == hpf_iterlimit) {
        stop(
          "Real-time HP filters did not converge in ", format(date),
          "; final relative error = ", format(error, scientific = TRUE)
        )
      }
    }
    db <- copy_period(db, result$simulation, i)
    if (show_progress && (date == origin || lubridate::quarter(date) == 4)) {
      message("BIMETS: completed through ", lubridate::year(date), "Q", lubridate::quarter(date))
    }
  }
  result$modelData <- db
  result$simulation <- db[names(result$simulation)]
  if (show_progress) {
    elapsed <- round(as.numeric(difftime(Sys.time(), started_at, units = "secs")), 1)
    message("BIMETS: complete (", elapsed, " seconds)")
  }
  result
}
