## US Smartphone TAM Predictive Model - Travis Nakano Data Science Practicum II Project

### Overview

The predictive model that was built in this project is based on univariate forecasting, initially when I started I tried to incorporate regressors to modify the univariate model however I ran into complications with length of history on my second data set which would have caused issues with the base model.  Overall I think the univariate model performed pretty well, and you can see two different techinques used to develop the model with slightly varying results.

### Motivation

I built the model to help predict market conditions for the smartphone market, it's important when planning sales volumes to see where the market is headed to adjust expectations for production.

### Data

The data used in this project has smartphone sales data for the US smartphone market broken out by week.  Additionally smartphone promotional data was gathered but not used due to the issues around data integrity before 2018.

### Analysis

1. Import data files into R

2. Clean Data
  *Update column naming to work with SQLDF package
  *Merge two data sets together
  *Run Shapiro test to check for normality
  *Modify data by using log to best adjust for normality

3. EDA
  *Check for data correlations between promo and volume
  *Negative correlation (suspect issues within aggregation)
  
4. Modeling
  *Build Holt Winters model and test against actuals
  *Build alternatrive ARIMA model to see which univariate model works best

5. Analysis
  *Found that while the Holt Winters model did best during the test the longer forecast showed very low prediction value suggesting market shrinkage next year.  I suspect this estimate to be low based on industry events, when comparing to the ARIMA model (which in testing performed only slightly worse) the ARIMA model predicted significantly higher results which seem to be in line with most industry analysts predictions.
