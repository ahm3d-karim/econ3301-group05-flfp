# Is women's work U-shaped in income? Developing countries and Pakistan

ECON 3301 Data Analytics Lab II, LUMS. Group 05: Ahmad Karim, Maram Bilal, Madiha Nasir, Muhammad Abdullah Iqbal.

We test whether female labour force participation is U-shaped in GDP per capita among developing countries (World Bank WDI, 1990-2022), and where Pakistan sits relative to the curve.

## How to run

1. Download `Project_Idea_A_Developing.do` and open it in Stata (we used Stata 18).
2. Run it. You don't need to change anything.

The do-file reads the data straight from this repository, so you need an internet connection. It installs `estout` and `coefplot` from SSC if you don't already have them. It takes about two minutes to run.

Outputs are saved in a new folder called `Output_Developing`, inside Stata's current working directory. That folder holds the log, tables T1-T5 (.rtf), figures F1-F13 (.png) and the cleaned panel (.dta).

## Data

| File | Contents |
|---|---|
| `data/WDI/wdi_idea_a.csv` | Main country-year panel: female LFP, GDP per capita (PPP), agriculture and services shares, fertility, female secondary enrolment, urban share |
| `data/WDI/wdi_country_income_groups.csv` | Current World Bank income group and region of each country |
| `data/WDI/wdi_indicator_dictionary.csv` | WDI indicator codes and names |
| `data/WB_extra/wdi_extra_lfp.csv` | Male LFP and the female-to-male LFP ratio (WDI) |
| `data/WB_extra/wb_income_history.csv` | Historical World Bank income group of each country in each year (from the World Bank's OGHIST file) |

Source: World Bank, World Development Indicators and the World Bank's historical income classification. Both are licensed CC BY 4.0.
