*==============================================================================
* ECON 3301 - Data Analytics Lab II - Final Project (Group 05)
* Narrowed version: is female labour force participation U-shaped in income
*                   AMONG DEVELOPING COUNTRIES, and where is Pakistan?
* Data  : World Development Indicators (country-year panel, 1990-2022),
*         downloaded from the World Bank when the file runs
* Level : country-year
*
* Structure
*   0. Setup
*   1. Download the data from the World Bank
*   2. Clean and build the panel
*   3. Data description and summary statistics
*   4. Main regressions (developing countries)
*   5. Robustness and comparison groups
*   6. Turning point and Pakistan
*   7. Figures
*   8. Extensions: lagged income, historical income groups, female-to-male
*      ratio and male participation, Pakistan against its region
*
* Navigation: each section starts with a "**#" line. In Stata's Do-file
* Editor these are bookmarks: use the Navigation list at the top of the
* editor to jump between sections.
*
* Headline model (d5): FLFP on log GDP per capita and its square, with country
* and year fixed effects and NO controls (total association). The controls
* (sector shares, fertility, enrolment, urbanisation) are likely channels of
* income ("bad controls"), so d6 adds them as a mechanism check.
* All results are associations, not causal effects.
*==============================================================================
clear all
set more off
capture log close

**# 0. SETUP
*------------------------------------------------------------------------------
* 0. SETUP  (nothing to change: open the file and run it)
*    The data are downloaded from the World Bank when the file runs, so it
*    works on any computer with Stata and an internet connection.
*    Two folders are created inside Stata's current working directory:
*      Data_Raw           the downloaded World Bank files and the raw panel
*      Output_Developing  log, tables, figures and the cleaned panel
*    Repository: https://github.com/ahm3d-karim/econ3301-group05-flfp
*------------------------------------------------------------------------------
global out   "`c(pwd)'/Output_Developing"
capture mkdir "$out"
di "Outputs will be saved in: $out"

log using "$out/Project_Developing.log", replace text

* User-written packages (install once if missing)
capture which esttab
if _rc ssc install estout, replace
capture which coefplot
if _rc ssc install coefplot, replace

**# 1. DOWNLOAD THE DATA FROM THE WORLD BANK
*------------------------------------------------------------------------------
* 1. DOWNLOAD THE DATA FROM THE WORLD BANK
*    Each WDI indicator is downloaded from the World Bank's data API as a zip
*    file. The zip holds three CSV files:
*      API_<code>_....csv                 the data: one row per country, one
*                                         column per year (1960 onwards)
*      Metadata_Country_API_<code>_....csv each country's region and current
*                                         income group (blank for aggregates
*                                         such as "World" or "South Asia")
*      Metadata_Indicator_API_<code>_....csv the indicator's definition
*    The World Bank's historical income groups come from its OGHIST.xlsx file.
*    Raw files are kept in Data_Raw so you can open and check them.
*------------------------------------------------------------------------------
global raw "`c(pwd)'/Data_Raw"
capture mkdir "$raw"
local home "`c(pwd)'"

* WDI indicators used in the project, and the short name each one gets
local codes  SL.TLF.CACT.FE.ZS NY.GDP.PCAP.PP.KD NV.AGR.TOTL.ZS NV.SRV.TOTL.ZS ///
             SP.DYN.TFRT.IN SE.SEC.ENRR.FE SP.URB.TOTL.IN.ZS                  ///
             SL.TLF.CACT.FM.ZS SL.TLF.CACT.MA.ZS
local names  flfp gdppc agri serv fert sec_enr urban fm_ratio flfp_male

local i = 0
foreach code of local codes {
    local ++i
    local name : word `i' of `names'
    di as text _n "Downloading `code' (`name') ..."

    * Download and unzip into its own folder
    capture mkdir "$raw/`code'"
    copy "https://api.worldbank.org/v2/en/indicator/`code'?downloadformat=csv" ///
         "$raw/`code'/`code'.zip", replace
    quietly cd "$raw/`code'"
    unzipfile "`code'.zip", replace
    quietly cd "`home'"

    * The data file's name ends in a version number, so look it up
    local f : dir "$raw/`code'" files "API_*.csv"
    local f = subinstr(`"`f'"', `"""', "", .)

    * Lines 1-4 are a short header (source, last updated); line 5 has the
    * variable names. Years become variables v5, v6, ... with the year as
    * their label, so we rename them yr1960, yr1961, ...
    import delimited "$raw/`code'/`f'", varnames(5) rowrange(6) clear ///
        encoding(utf-8) stringcols(1 2 3 4) asdouble
    foreach v of varlist _all {
        local lab : variable label `v'
        if regexm("`lab'", "^[12][0-9][0-9][0-9]$") rename `v' yr`lab'
    }
    keep countrycode yr*

    * Wide (one column per year) to long (one row per country-year)
    reshape long yr, i(countrycode) j(year)
    rename yr `name'
    label var `name' "`code'"
    tempfile d`i'
    save `d`i''
}

* Region and current income group, from the metadata file of the first
* indicator (the same list comes with every indicator)
local f : dir "$raw/SL.TLF.CACT.FE.ZS" files "Metadata_Country_*.csv"
local f = subinstr(`"`f'"', `"""', "", .)
* (bindquote(strict): some country notes contain line breaks inside quotes)
import delimited "$raw/SL.TLF.CACT.FE.ZS/`f'", varnames(1) clear ///
    encoding(utf-8) stringcols(_all) bindquote(strict)
rename (tablename incomegroup) (country income_level)
keep countrycode country region income_level
* Aggregates ("World", "South Asia", "High income", ...) have no income group
drop if income_level == ""
gen income_level_code = "LIC" if income_level == "Low income"
replace income_level_code = "LMC" if income_level == "Lower middle income"
replace income_level_code = "UMC" if income_level == "Upper middle income"
replace income_level_code = "HIC" if income_level == "High income"
assert income_level_code != ""
tempfile groups
save `groups'

* Join the indicators into one country-year panel. Countries only (the
* merge with the group list drops the regional and world aggregates).
use `d1', clear
forvalues j = 2/`i' {
    merge 1:1 countrycode year using `d`j'', nogenerate
}
merge m:1 countrycode using `groups', keep(match) nogenerate
order countrycode country year
sort countrycode year
save "$raw/wdi_panel_raw.dta", replace

* Historical income groups: OGHIST.xlsx, sheet "Country Analytical History".
* Rows 1-11 are titles and income thresholds; each row from 12 is a country;
* column C is data year 1987, D is 1988, and so on. Cells hold L, LM, UM or
* H; ".." means not classified that year.
copy "https://datacatalogfiles.worldbank.org/ddh-published/0037712/DR0090754/OGHIST.xlsx" ///
     "$raw/OGHIST.xlsx", replace
import excel "$raw/OGHIST.xlsx", sheet("Country Analytical History") ///
    cellrange(A12) allstring clear
rename A countrycode
keep if strlen(countrycode) == 3 & B != ""     // countries only, no notes
drop B
local y = 1987
foreach v of varlist _all {
    if "`v'" == "countrycode" continue
    rename `v' g`y'
    local ++y
}
reshape long g, i(countrycode) j(year)
rename g wb_group
replace wb_group = strtrim(wb_group)
replace wb_group = "LM" if wb_group == "LM*"   // former Yemens combined
replace wb_group = ""   if wb_group == ".."
drop if wb_group == ""
assert inlist(wb_group, "L", "LM", "UM", "H")
save "$raw/wb_income_history.dta", replace

**# 2. CLEAN AND BUILD THE PANEL
*------------------------------------------------------------------------------
* 2. CLEAN AND BUILD THE PANEL
*------------------------------------------------------------------------------
use "$raw/wdi_panel_raw.dta", clear

* Sample window: 1990-2022 (later years have many missing values)
keep if inrange(year, 1990, 2022)

* Checks: one row per country-year, and every country has an income group
isid countrycode year
assert !missing(income_level)

* Variable labels
label var flfp    "Female labour force participation (% women 15+)"
label var gdppc   "GDP per capita, PPP (constant 2021 int. $)"
label var agri    "Agriculture, % of GDP"
label var serv    "Services, % of GDP"
label var fert    "Fertility rate (births per woman)"
label var sec_enr "Female secondary enrolment (gross, %)"
label var urban   "Urban population (%)"
label var fm_ratio  "Female-to-male LFP ratio (%)"
label var flfp_male "Male labour force participation (% of men 15+)"
* Note: gross enrolment can exceed 100 (over-age and repeating students).
* We leave it uncapped.

* Main regressors
gen lgdp  = ln(gdppc)
gen lgdp2 = lgdp^2
label var lgdp  "Log GDP per capita"
label var lgdp2 "Log GDP per capita, squared"

* Panel identifiers
encode countrycode, gen(cid)
xtset cid year
isid cid year

* --- Sample definitions -------------------------------------------------------
* (a) Developing = low- or middle-income in the CURRENT World Bank list.
gen byte dev = (income_level != "High income")
label var dev "Developing (low/middle income, current WB classification)"

* (b) Robustness: developing AT THE START of the window. Using today's list
*     drops countries that grew rich during 1990-2022 (e.g. South Korea),
*     which selects on the outcome of growth. Here a country counts as
*     developing if its GDP per capita in its first observed year was below
*     $20,000 (PPP, 2021 $), a rough PPP equivalent of the high-income line.
*     This cut-off is approximate; it is a check, not the main definition.
bysort cid (year): egen first_yr = min(cond(!missing(gdppc), year, .))
bysort cid: egen gdppc_start = max(cond(year == first_yr, gdppc, .))
gen byte dev_start = gdppc_start < 20000 if !missing(gdppc_start)
label var dev_start "Developing at start (GDP pc < $20k PPP in first year)"
drop first_yr

gen byte southasia = inlist(countrycode, "PAK", "IND", "BGD", "LKA", "NPL")
label var southasia "South Asia (PAK, IND, BGD, LKA, NPL)"

* Complete-case samples
gen byte insamp  = !missing(flfp, lgdp, agri, serv, fert, sec_enr, urban)
gen byte insamp2 = !missing(flfp, lgdp, agri, serv, fert, urban)   // no enrolment
gen byte core    = !missing(flfp, lgdp)                            // max sample
label var insamp  "Complete case, all controls"
label var insamp2 "Complete case, without enrolment"
label var core    "FLFP and income observed"

save "$out/panel_developing.dta", replace

**# 3. DATA DESCRIPTION AND SUMMARY STATISTICS
*------------------------------------------------------------------------------
* 3. DATA DESCRIPTION AND SUMMARY STATISTICS
*------------------------------------------------------------------------------
* How many countries and country-years in each sample?
foreach s in "core" "insamp" {
    quietly count if `s' & dev
    local n = r(N)
    egen tag = tag(cid) if `s' & dev
    quietly count if tag == 1
    di "Developing countries, sample `s': `n' country-years, " r(N) " countries"
    drop tag
}
tab dev_start dev if core & year == 2022

* Missing data among developing countries
misstable summarize flfp gdppc agri serv fert sec_enr urban if dev

* Table 1: summary statistics, developing countries, main sample
estpost summarize flfp gdppc agri serv fert sec_enr urban if insamp & dev
esttab using "$out/T1_summary_dev.rtf", replace ///
    cells("count mean(fmt(2)) sd(fmt(2)) min(fmt(2)) max(fmt(2))") ///
    nomtitle nonumber label title("Summary statistics: developing countries")

* Summary by income band
tabstat flfp gdppc agri serv fert if core & dev, by(income_level) ///
    stat(n mean sd) format(%9.2f)

**# 4. MAIN REGRESSIONS
*------------------------------------------------------------------------------
* 4. MAIN REGRESSIONS (developing countries, common complete-case sample)
*    U-shape  <=>  coefficient on lgdp < 0 and on lgdp2 > 0
*    Standard errors clustered by country throughout.
*------------------------------------------------------------------------------
eststo clear
* (1) Pooled OLS
eststo d1: reg flfp lgdp lgdp2 if insamp & dev, vce(cluster cid)
* (2) Pooled OLS + controls
eststo d2: reg flfp lgdp lgdp2 agri serv fert sec_enr urban if insamp & dev, ///
    vce(cluster cid)
* (3) Country FE: each country compared with itself over time
eststo d3: xtreg flfp lgdp lgdp2 if insamp & dev, fe vce(cluster cid)
* (4) Country FE + controls
eststo d4: xtreg flfp lgdp lgdp2 agri serv fert sec_enr urban if insamp & dev, ///
    fe vce(cluster cid)
* (5) HEADLINE: country FE + year FE, no controls (total association)
eststo d5: xtreg flfp lgdp lgdp2 i.year if insamp & dev, fe vce(cluster cid)
* (6) Mechanism check: country FE + year FE + controls
eststo d6: xtreg flfp lgdp lgdp2 agri serv fert sec_enr urban i.year ///
    if insamp & dev, fe vce(cluster cid)

* Joint test of the income terms (lgdp and lgdp2 are highly collinear, so
* their separate SEs are large; judge them together)
foreach m in d1 d2 d3 d4 d5 d6 {
    quietly estimates restore `m'
    test lgdp lgdp2
    local pj = r(p)
    estadd scalar p_joint = `pj' : `m'
}

* Fixed-effect indicator rows for the table
foreach m in d1 d2 {
    estadd local cfe "No" : `m'
    estadd local yfe "No" : `m'
}
foreach m in d3 d4 {
    estadd local cfe "Yes" : `m'
    estadd local yfe "No"  : `m'
}
foreach m in d5 d6 {
    estadd local cfe "Yes" : `m'
    estadd local yfe "Yes" : `m'
}

esttab d1 d2 d3 d4 d5 d6 using "$out/T2_main_dev.rtf", replace ///
    b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) label r2 drop(*.year) ///
    scalars("p_joint Joint p-value, income terms" "cfe Country FE" ///
            "yfe Year FE" "N_clust Countries") sfmt(%9.3f %9.0f) ///
    mtitles("OLS" "OLS+ctrl" "FE" "FE+ctrl" "Headline (FE+year)" ///
            "Mechanisms (FE+year+ctrl)") ///
    title("Female LFP and log GDP per capita: developing countries") ///
    addnotes("Standard errors clustered by country." ///
             "Headline: FE+year. Controls may be channels of income, so the last column is a mechanism check.")

* Turning point: lgdp* = -b1/(2*b2) in log GDP per capita; exp() gives
* GDP per capita in PPP, constant 2021 $. Delta-method 95% CIs.
foreach m in d2 d5 d6 {
    quietly estimates restore `m'
    di _n "Turning point, model `m':"
    nlcom (turning_log: -_b[lgdp]/(2*_b[lgdp2])) ///
          (turning_gdppc: exp(-_b[lgdp]/(2*_b[lgdp2])))
}

**# 5. ROBUSTNESS AND COMPARISON GROUPS
*------------------------------------------------------------------------------
* 5. ROBUSTNESS AND COMPARISON GROUPS (all country + year FE)
*------------------------------------------------------------------------------
* (main models d1-d6 stay stored: the figures in section 7 use them)
* (r1) Larger sample: drop enrolment (the control with the most gaps), keep
*      the other controls
eststo r1: xtreg flfp lgdp lgdp2 agri serv fert urban i.year if insamp2 & dev, ///
    fe vce(cluster cid)
* (r2) Largest sample: no controls, every developing country-year with data
eststo r2: xtreg flfp lgdp lgdp2 i.year if core & dev, fe vce(cluster cid)
* (r3) Developing at the start of the window instead of today
eststo r3: xtreg flfp lgdp lgdp2 i.year if insamp & dev_start == 1, ///
    fe vce(cluster cid)
* (r4) Comparison: all countries
eststo r4: xtreg flfp lgdp lgdp2 i.year if insamp, fe vce(cluster cid)
* (r5) Comparison: high-income countries
eststo r5: xtreg flfp lgdp lgdp2 i.year if insamp & !dev, fe vce(cluster cid)
* (r6) South Asia only. 5 countries = 5 clusters, so the SEs and stars are
*      unreliable. Descriptive only.
eststo r6: xtreg flfp lgdp lgdp2 i.year if insamp & southasia, ///
    fe vce(cluster cid)

foreach m in r1 r2 r3 r4 r5 r6 {
    quietly estimates restore `m'
    test lgdp lgdp2
    local pj = r(p)
    estadd scalar p_joint = `pj' : `m'
}

esttab r1 r2 r3 r4 r5 r6 using "$out/T3_robustness_dev.rtf", replace ///
    b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) label r2 drop(*.year) ///
    scalars("p_joint Joint p-value, income terms" "N_clust Countries") ///
    sfmt(%9.3f %9.0f) ///
    mtitles("No enrolment ctrl" "Max sample" "Dev. at start" ///
            "All countries" "High income" "South Asia") ///
    title("Robustness and comparison groups (country + year FE)") ///
    addnotes("Columns 1-3: developing countries. Columns 4-6: comparison groups." ///
             "South Asia has only 5 clusters: descriptive only, do not read significance.")

foreach m in r2 r3 r4 {
    quietly estimates restore `m'
    di _n "Turning point, model `m':"
    nlcom (turning_log: -_b[lgdp]/(2*_b[lgdp2])) ///
          (turning_gdppc: exp(-_b[lgdp]/(2*_b[lgdp2])))
}

* Flexible-form checks: is the U only there because we forced a quadratic?
gen lgdp3 = lgdp^3
gen ibin  = floor(lgdp)      // bins of log income, roughly x2.7 in dollars
* (f1) Add a cubic term
eststo f1: xtreg flfp lgdp lgdp2 lgdp3 i.year if insamp & dev, fe vce(cluster cid)
test lgdp3
* (f2) Income bins, no assumed shape (base bin 8 = GDP pc about $3,000-8,100)
eststo f2: xtreg flfp ib8.ibin i.year if insamp & dev, fe vce(cluster cid)
testparm i.ibin
esttab f1 f2 using "$out/T4_flexible_dev.rtf", replace b(3) se(3) ///
    star(* 0.10 ** 0.05 *** 0.01) label r2 drop(*.year) ///
    scalars("N_clust Countries") sfmt(%9.0f) ///
    mtitles("Cubic" "Income bins") ///
    title("Flexible-form checks: developing countries (country + year FE)")

**# 6. TURNING POINT AND PAKISTAN
*------------------------------------------------------------------------------
* 6. TURNING POINT AND PAKISTAN
*------------------------------------------------------------------------------
* Turning point from the headline model
quietly xtreg flfp lgdp lgdp2 i.year if insamp & dev, fe vce(cluster cid)
scalar tp_log = -_b[lgdp]/(2*_b[lgdp2])
scalar tp_inc = exp(tp_log)
local tpl     = tp_log
local tp_lab  = "$" + string(round(tp_inc, 100), "%9.0fc")
di "Headline turning point: log GDP pc = " tp_log ", GDP pc = " tp_inc

* Is the turning point inside the observed income range?
quietly summarize lgdp if insamp & dev, detail
di "Developing countries, log income: min " r(min) ", p5 " r(p5) ///
   ", median " r(p50) ", p95 " r(p95) ", max " r(max)

* Who is below the turning point, and how has that changed?
gen byte below_tp = lgdp < tp_log if core & dev
label var below_tp "Income below the turning point"
foreach y in 1995 2008 2022 {
    quietly summarize below_tp if year == `y'
    di "Share of developing countries below the turning point in `y': " ///
       %4.2f r(mean) " (N = " r(N) ")"
}

* Pakistan and South Asia relative to the turning point, 2022
list countrycode gdppc flfp below_tp if southasia & year == 2022, noobs

* Gap from the curve: 2022 cross-section of developing countries
quietly reg flfp lgdp lgdp2 if year == 2022 & core & dev
predict flfp_hat if e(sample), xb
gen gap22 = flfp - flfp_hat if e(sample)
label var flfp_hat "Predicted FLFP, 2022 cross-section (%)"
label var gap22    "Actual minus predicted FLFP, 2022 (pp)"
list countrycode gdppc flfp flfp_hat gap22 if southasia & year == 2022, noobs
preserve
    keep if year == 2022 & !missing(gap22)
    gsort gap22
    di "Developing countries furthest BELOW the curve in 2022:"
    list country gdppc flfp gap22 in 1/10, noobs
    quietly count
    local n22 = r(N)
    gen rank = _n
    quietly summarize rank if countrycode == "PAK"
    di "Pakistan's rank from the bottom: " r(mean) " of `n22'"
restore

**# 7. FIGURES
*------------------------------------------------------------------------------
* 7. FIGURES (all developing countries unless stated)
*------------------------------------------------------------------------------
* F1: raw data with a quadratic fit and the turning point
twoway (scatter flfp lgdp if core & dev, msize(tiny) mcolor(gs10%40)) ///
       (qfit flfp lgdp if core & dev, lcolor(maroon) lwidth(medthick)), ///
    xline(`tpl', lpattern(dash) lcolor(gs6)) ///
    xtitle("Log GDP per capita (PPP)") ytitle("Female LFP (%)") ///
    title("Female participation and income, developing countries") ///
    legend(order(1 "Country-years, 1990-2022" 2 "Quadratic fit")) ///
    note("Dashed line: headline turning point (about `tp_lab')." ) ///
    scheme(s1mono)
graph export "$out/F1_scatter_dev.png", replace width(1600)

* F2: predicted participation from the headline model, with 95% CI
quietly xtreg flfp c.lgdp##c.lgdp i.year if insamp & dev, fe vce(cluster cid)
quietly summarize lgdp if insamp & dev, detail
local lo = round(r(p1), 0.5)
local hi = round(r(p99), 0.5)
quietly margins, at(lgdp = (`lo'(0.25)`hi'))
marginsplot, recast(line) recastci(rarea) ///
    plotopts(lcolor(maroon) lwidth(thick)) ciopts(color(maroon%25) lwidth(none)) ///
    xline(`tpl', lpattern(dash) lcolor(gs6)) ///
    xtitle("Log GDP per capita (PPP)") ytitle("Predicted female LFP (%)") ///
    title("Estimated U, developing countries (95% CI)") ///
    note("Country and year fixed effects, no controls. Dashed line: turning point.") ///
    scheme(s1mono)
graph export "$out/F2_fitted_dev.png", replace width(1600)

* F3: income coefficients across specifications
coefplot (d5, label("Headline: FE+year")) (d6, label("+ controls")) ///
         (r2, label("Max sample")) (r3, label("Dev. at start")) ///
         (r5, label("High income (contrast)")), ///
    keep(lgdp lgdp2) xline(0) ///
    title("Income coefficients across specifications (95% CI)") scheme(s1mono)
graph export "$out/F3_coefplot_dev.png", replace width(1600)

* F4: income bins (no assumed shape)
coefplot f2, keep(*.ibin) vertical baselevels yline(0) ///
    coeflabels(6.ibin = "<$1.1k" 7.ibin = "$1.1-3k" 8.ibin = "$3-8.1k" ///
               9.ibin = "$8.1-22k" 10.ibin = "$22-60k") ///
    xtitle("GDP per capita (PPP) bin") ///
    ytitle("FLFP relative to the $3-8.1k bin (pp)") ///
    title("Income-bin check, developing countries") scheme(s1mono)
graph export "$out/F4_bins_dev.png", replace width(1600)

* F5: Pakistan against the developing-country curve, 2022
twoway (scatter flfp lgdp if year == 2022 & core & dev, mcolor(gs10) msize(small)) ///
       (qfit flfp lgdp if year == 2022 & core & dev, lcolor(maroon)) ///
       (scatter flfp lgdp if year == 2022 & southasia, mcolor(navy) ///
            msymbol(D) mlabel(countrycode) mlabcolor(navy)), ///
    xline(`tpl', lpattern(dash) lcolor(gs6)) ///
    xtitle("Log GDP per capita (PPP)") ytitle("Female LFP (%)") ///
    title("Developing countries in 2022: South Asia below the curve") ///
    legend(order(1 "Developing countries" 2 "Quadratic fit" 3 "South Asia")) ///
    note("Dashed line: headline turning point (about `tp_lab').") scheme(s1mono)
graph export "$out/F5_pakistan_2022.png", replace width(1600)

* F6: South Asia over time
twoway (line flfp year if countrycode=="PAK", lwidth(thick) lcolor(green)) ///
       (line flfp year if countrycode=="IND") (line flfp year if countrycode=="BGD") ///
       (line flfp year if countrycode=="LKA") (line flfp year if countrycode=="NPL"), ///
    xtitle("Year") ytitle("Female LFP (%)") ///
    legend(order(1 "Pakistan" 2 "India" 3 "Bangladesh" 4 "Sri Lanka" 5 "Nepal")) ///
    title("Female participation in South Asia") scheme(s1mono)
graph export "$out/F6_southasia.png", replace width(1600)

* F7: case paths against the turning point (Pakistan, India, Bangladesh,
*     Indonesia, Albania). Dashed line = turning point; labels = years.
gen yrlab = string(year) if inlist(year, 1990, 2005, 2022)
local graphs ""
local i = 0
foreach c in PAK IND BGD IDN ALB {
    local ++i
    quietly levelsof country if countrycode == "`c'", local(nm) clean
    quietly summarize lgdp if countrycode == "`c'" & core
    local xlo = min(r(min), `tpl') - 0.1
    local xhi = max(r(max), `tpl') + 0.35
    quietly summarize flfp if countrycode == "`c'" & core
    local pad = (r(max) - r(min)) * 0.12 + 0.5
    local ylo = r(min) - `pad'
    local yhi = r(max) + `pad'
    twoway (connected flfp lgdp if countrycode=="`c'" & core, lcolor(navy) ///
            mcolor(navy) msize(small) mlabel(yrlab) mlabcolor(black) ///
            mlabsize(small) mlabposition(12)) ///
           (pci `ylo' `tpl' `yhi' `tpl', lpattern(dash) lcolor(maroon)), ///
        xscale(range(`xlo' `xhi')) yscale(range(`ylo' `yhi')) ///
        xlabel(, format(%3.1f)) title("`nm'", size(medium)) ///
        xtitle("Log GDP per capita") ytitle("Female LFP (%)") ///
        legend(off) scheme(s1mono) name(g`i', replace)
    local graphs "`graphs' g`i'"
}
graph combine `graphs', cols(3) scheme(s1mono) ///
    note("Dashed line: headline turning point (about `tp_lab'). Labels: 1990, 2005, 2022.")
graph export "$out/F7_case_paths.png", replace width(2000)
drop yrlab

* F8: mechanism - structure of the economy by income band (developing only)
graph bar (mean) agri serv if inlist(year, 1990, 2022) & dev & !missing(agri, serv), ///
    over(year) over(income_level_code, relabel(1 "Low" 2 "Lower-middle" 3 "Upper-middle")) ///
    ytitle("% of GDP") legend(order(1 "Agriculture" 2 "Services")) ///
    title("Structure of the economy by income band") scheme(s1mono)
graph export "$out/F8_structure_dev.png", replace width(1600)

* F9: developing vs high-income curves (contrast), relative to log GDP pc = 9
quietly estimates restore d5
local b1d = _b[lgdp]
local b2d = _b[lgdp2]
quietly summarize lgdp if insamp & dev, detail
local d_lo = r(p5)
local d_hi = r(p95)
quietly estimates restore r5
local b1h = _b[lgdp]
local b2h = _b[lgdp2]
quietly summarize lgdp if insamp & !dev, detail
local h_lo = r(p5)
local h_hi = r(p95)
twoway (function y = `b1d'*x + `b2d'*x^2 - (`b1d'*9 + `b2d'*81), ///
            range(`d_lo' `d_hi') lcolor(maroon) lwidth(thick)) ///
       (function y = `b1h'*x + `b2h'*x^2 - (`b1h'*9 + `b2h'*81), ///
            range(`h_lo' `h_hi') lcolor(navy) lwidth(thick)), ///
    yline(0, lcolor(gs12)) xline(`tpl', lpattern(dash) lcolor(gs6)) ///
    xtitle("Log GDP per capita (PPP)") ///
    ytitle("Change in FLFP vs. GDP pc of about $8,100 (pp)") ///
    title("Estimated curve: developing vs high-income countries") ///
    legend(order(1 "Developing" 2 "High income")) ///
    note("Country and year FE, no controls. Each curve drawn over its group's 5th-95th income percentile.") ///
    scheme(s1mono)
graph export "$out/F9_dev_vs_high.png", replace width(1600)

* F10: share of developing countries below the turning point, by year
preserve
    keep if core & dev
    collapse (mean) share = below_tp, by(year)
    replace share = share * 100
    twoway (line share year, lcolor(maroon) lwidth(thick)), ///
        xtitle("Year") ytitle("% of developing countries below the turning point") ///
        title("Developing countries moving past the turning point") ///
        ylabel(0(20)100) scheme(s1mono)
    graph export "$out/F10_share_below_dev.png", replace width(1600)
restore

**# 8. EXTENSIONS
*------------------------------------------------------------------------------
* 8. EXTENSIONS
*    (a) Lagged income        reverse causality: women's work also raises GDP
*    (b) Historical WB groups today's list selects on growth; $20k is arbitrary
*    (c) Female-to-male ratio and male participation: is the U about women?
*    (d) Pakistan against its region: is the gap regional or Pakistan-specific?
*    Extra data (World Bank, downloaded in section 1):
*      fm_ratio, flfp_male   SL.TLF.CACT.FM.ZS (F/M LFP ratio, %) and
*                            SL.TLF.CACT.MA.ZS (male LFP, %), already in the panel
*      wb_income_history.dta OGHIST.xlsx "Country Analytical History": WB income
*                            group of each country in each data year
*    All models: country + year FE, no controls (as in d5), clustered SEs.
*------------------------------------------------------------------------------

* Start again from the clean panel saved in section 2 (stored models are kept)
use "$out/panel_developing.dta", clear
merge 1:1 countrycode year using "$raw/wb_income_history.dta", ///
    keep(master match) nogenerate
xtset cid year

* (b) Developing by the World Bank's own historical classification
*     dev_hist: low/middle income in the first year the country is classified
*     dev_year: low/middle income in that year (time-varying)
gen byte dev_year = inlist(wb_group, "L", "LM", "UM") if !missing(wb_group)
gen yclass = year if !missing(wb_group)
bysort cid: egen yfirst = min(yclass)
gen g_first = wb_group if year == yfirst
bysort cid (g_first): replace g_first = g_first[_N]
gen byte dev_hist = inlist(g_first, "L", "LM", "UM") if g_first != ""
label var dev_year "Low/middle income in that year (WB historical)"
label var dev_hist "Low/middle income at start (WB historical)"
drop yclass yfirst
xtset cid year
tab dev dev_hist if year == 2022, missing

* (a) Income five years earlier. Today's female work cannot cause income five
*     years ago, so this eases (does not remove) reverse causality.
gen lgdp_l5   = L5.lgdp
gen lgdp_l5sq = lgdp_l5^2
eststo x2: xtreg flfp lgdp_l5 lgdp_l5sq i.year if core & dev, fe vce(cluster cid)

* (b) Historical classification
eststo x4a: xtreg flfp lgdp lgdp2 i.year if core & dev_hist == 1, fe vce(cluster cid)
eststo x4b: xtreg flfp lgdp lgdp2 i.year if core & dev_year == 1, fe vce(cluster cid)

* (c) Female-to-male ratio as the outcome, and male participation
eststo x3:  xtreg fm_ratio  lgdp lgdp2 i.year if core & dev, fe vce(cluster cid)
eststo x3m: xtreg flfp_male lgdp lgdp2 i.year if core & dev, fe vce(cluster cid)

* Joint tests and turning points
foreach m in x4a x4b x3 x3m {
    quietly estimates restore `m'
    quietly test lgdp lgdp2
    local pj = r(p)
    estadd scalar p_joint = `pj' : `m'
    local tp = exp(-_b[lgdp]/(2*_b[lgdp2]))
    estadd scalar tp = `tp' : `m'
    di _n "Turning point, model `m':"
    nlcom (turning_gdppc: exp(-_b[lgdp]/(2*_b[lgdp2])))
}
quietly estimates restore x2
quietly test lgdp_l5 lgdp_l5sq
local pj = r(p)
estadd scalar p_joint = `pj' : x2
local tp = exp(-_b[lgdp_l5]/(2*_b[lgdp_l5sq]))
estadd scalar tp = `tp' : x2
di _n "Turning point, model x2 (lagged income):"
nlcom (turning_gdppc: exp(-_b[lgdp_l5]/(2*_b[lgdp_l5sq])))

esttab d5 x2 x4a x4b x3 x3m using "$out/T5_extensions_dev.rtf", replace ///
    b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) label r2 drop(*.year) ///
    rename(lgdp_l5 lgdp lgdp_l5sq lgdp2) ///
    scalars("p_joint Joint p-value, income terms" "tp Turning point (PPP $)" ///
            "N_clust Countries") sfmt(%9.3f %9.0fc %9.0f) ///
    mtitles("Headline" "Lagged income" "WB dev at start" "WB dev that year" ///
            "F/M ratio" "Male LFP") ///
    title("Extensions: developing countries (country + year FE, no controls)") ///
    addnotes("Columns 1-4: outcome = female LFP; column 5: female-to-male ratio; column 6: male LFP." ///
             "Column 2: income 5 years earlier. SEs clustered by country.")

* (d) Pakistan against its region, 2022 cross-section of developing countries
*     The World Bank now puts Pakistan in "Middle East, North Africa,
*     Afghanistan & Pakistan", so we also benchmark it against South Asia.
gen reg = strtrim(region)
encode reg, gen(regn)
quietly reg flfp lgdp lgdp2 if year == 2022 & core & dev
predict hat_noreg if e(sample), xb
quietly reg flfp lgdp lgdp2 i.regn if year == 2022 & core & dev
predict hat_reg if e(sample), xb
gen gap_noreg = flfp - hat_noreg
gen gap_reg   = flfp - hat_reg
* Pakistan with the South Asia region effect instead of its WB region
quietly levelsof regn if reg == "South Asia", local(sa)
gen regn_sa = cond(countrycode == "PAK", `sa', regn)
preserve
    replace regn = regn_sa
    predict hat_sa if year == 2022 & countrycode == "PAK", xb
    quietly summarize hat_sa
    local hsa = r(mean)
    quietly summarize flfp if year == 2022 & countrycode == "PAK"
    di "Pakistan 2022, benchmarked to South Asia: predicted " %5.1f `hsa' ///
       ", gap " %5.1f (r(mean) - `hsa') " points"
restore
list countrycode reg flfp hat_noreg gap_noreg hat_reg gap_reg ///
    if inlist(countrycode, "PAK", "IND", "BGD", "LKA", "NPL") & year == 2022, ///
    noobs abbreviate(12)
foreach g in gap_noreg gap_reg {
    preserve
        keep if year == 2022 & !missing(`g')
        sort `g'
        gen rank = _n
        quietly summarize rank if countrycode == "PAK"
        di "Pakistan rank from the bottom, `g': " r(mean) " of " _N
    restore
}

* F11: female-to-male ratio against income (is the U about women?)
twoway (scatter fm_ratio lgdp if core & dev, msize(tiny) mcolor(gs10%40)) ///
       (qfit fm_ratio lgdp if core & dev, lcolor(maroon) lwidth(medthick)), ///
    xtitle("Log GDP per capita (PPP)") ytitle("Female-to-male LFP ratio (%)") ///
    title("Female-to-male participation ratio and income") ///
    legend(order(1 "Country-years, 1990-2022" 2 "Quadratic fit")) scheme(s1mono)
graph export "$out/F11_fm_ratio.png", replace width(1600)

* F12: average gap from the curve by World Bank region, 2022
preserve
    keep if year == 2022 & !missing(gap_noreg)
    collapse (mean) gap_noreg, by(regn)
    decode regn, gen(rname)
    replace rname = "Middle East, N. Africa, Afg. & Pak." if strpos(rname, "Middle East")
    replace rname = "Latin America & Caribbean" if strpos(rname, "Latin")
    list rname gap_noreg, noobs
    graph hbar (mean) gap_noreg, over(rname, sort(1) label(labsize(small))) ///
        ytitle("Average gap from the curve, 2022 (pp)") ///
        title("Average gap from the curve, by region") ///
        bar(1, color(navy)) scheme(s1mono) ///
        note("Developing countries, 2022. Gap = actual minus predicted female LFP.")
    graph export "$out/F12_region_gaps.png", replace width(1600)
restore

* F13: Pakistan's path on the developing-country curve, 1990-2022
gen yrlab = string(year) if countrycode == "PAK" & inlist(year, 1990, 2022)
twoway (scatter flfp lgdp if core & dev, msize(tiny) mcolor(gs12%40)) ///
       (qfit flfp lgdp if core & dev, lcolor(maroon) lwidth(medthick)) ///
       (connected flfp lgdp if countrycode == "PAK" & core, lcolor(navy) ///
            mcolor(navy) msize(small) mlabel(yrlab) mlabcolor(navy) ///
            mlabposition(4) mlabsize(small)), ///
    xtitle("Log GDP per capita (PPP)") ytitle("Female LFP (%)") ///
    title("Pakistan's path, 1990-2022, against the curve") ///
    legend(order(1 "Developing countries" 2 "Quadratic fit" 3 "Pakistan")) ///
    scheme(s1mono)
graph export "$out/F13_pakistan_path.png", replace width(1600)
drop yrlab

**# End
*------------------------------------------------------------------------------
log close
