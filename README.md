# Is women's work U-shaped in income? Developing countries and Pakistan

ECON 3301 Data Analytics Lab II, LUMS. Group 05: Ahmad Karim, Maram Bilal, Madiha Nasir, Muhammad Abdullah Iqbal.

We test whether female labour force participation is U-shaped in GDP per capita among developing countries (World Bank WDI, 1990-2022), and where Pakistan sits relative to the curve.

## How to run

1. Download `Project_Idea_A_Developing.do` and open it in Stata (we used Stata 18).
2. Run it. You don't need to change anything.

The do-file downloads the data itself from the World Bank, cleans it, and then runs the analysis, so you need an internet connection. It installs `estout` and `coefplot` from SSC if you don't already have them. It takes about three minutes to run.

Two folders are created inside Stata's current working directory:

- `Data_Raw`: the downloaded World Bank files (one zip per WDI indicator, OGHIST.xlsx) and the raw panel before cleaning.
- `Output_Developing`: the log, tables T1-T5 (.rtf), figures F1-F13 (.png) and the cleaned panel (.dta).

Each section of the do-file starts with a `**#` line. Stata's Do-file Editor shows these as bookmarks in its Navigation list, so you can jump between sections.

## Data

The do-file downloads these from the World Bank:

| Source | What we use |
|---|---|
| World Development Indicators (data API, one zip per indicator) | Female LFP (SL.TLF.CACT.FE.ZS), GDP per capita PPP (NY.GDP.PCAP.PP.KD), agriculture and services shares (NV.AGR.TOTL.ZS, NV.SRV.TOTL.ZS), fertility (SP.DYN.TFRT.IN), female secondary enrolment (SE.SEC.ENRR.FE), urban share (SP.URB.TOTL.IN.ZS), female-to-male LFP ratio (SL.TLF.CACT.FM.ZS), male LFP (SL.TLF.CACT.MA.ZS); plus each country's region and current income group |
| World Bank historical income classification (OGHIST.xlsx) | Each country's income group in each year |

The `data` folder holds the copy of the data we used for our slides and brief, for reference. The do-file does not need it. The World Bank revises its data from time to time, so a later download may give slightly different numbers.

Source: World Bank, World Development Indicators and the World Bank's historical income classification. Both are licensed CC BY 4.0.
