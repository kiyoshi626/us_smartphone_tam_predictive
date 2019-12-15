library("readxl")
library(sqldf)
library("PerformanceAnalytics")
library(ggplot2)
library(forecast)
library(stats)
library(TTR)

#Import two data sets
sales <- read_excel('/Users/travisnakano/Downloads/handset_sales.xlsx')
promo <- read_excel('/Users/travisnakano/Downloads/Handset (11).xls')

#rename columns for use with SQLDF package
colnames(promo)[colnames(promo)=="Start Date"] <- "start_date"
colnames(promo)[colnames(promo)=="End Date"] <- "end_date"
colnames(promo)[colnames(promo)=="Promo Type"] <- "promo_type"
promo$Carrier <- as.character(promo$Carrier)
promo$Carrier[promo$Carrier == "Verizon Wireless"] <- "Verizon"
promo$Carrier[promo$Carrier == "U.S. Cellular"] <- "US Cellular"
colnames(sales)[colnames(sales)=="Week Starting"] <- "week_starting"
colnames(sales)[colnames(sales)=="Online Price (After All Discounts)"] <- "MSRP"
colnames(sales)[colnames(sales)=="Weeks Since Launch At Operator"] <- "weeks_since_launch"
colnames(sales)[colnames(sales)=="Calender Week #"] <- "week_num"
colnames(sales)[colnames(sales)=="Device Type"] <- "device_type"

#Join dataframes together
data <- sqldf('SELECT *
              FROM sales a
              LEFT JOIN promo b
              ON a.week_starting BETWEEN b.start_date AND b.end_date
              AND a.Model = b.Model
              AND a.Operator = b.carrier
              AND a.Country = "US"
              WHERE device_type = "Smartphone"')
#replace NA with 0 to correct errors in promo value calculation
data[is.na(data)] <- 0

#adjust data promo values based on type of promotion BOGO is buy one get one and should only be valued at 50% of offer, trade in doesn't apply to all sales and estimated 20% value is applied.
data <- sqldf('SELECT
               Year,
               week_starting,
               weeks_since_launch,
               week_num,
               Operator, 
               Manufacturer, 
               Model, 
               OS, 
               ROUND(Quantity, 2) AS quantity,
               promo_type,
               MSRP,
               CASE
               WHEN promo_type = "BOGO" THEN Value/2
               WHEN promo_type = "Trade-in" THEN value/5
               ELSE Value END AS value
               FROM data')

#Create discount percentage metric to normalize discounts
data <- sqldf('SELECT
               Year, 
               week_starting,
               weeks_since_launch,
               week_num,
               Operator,
               Manufacturer,
               Model,
               OS,
               quantity,
               promo_type,
               CASE WHEN MSRP <300 THEN "Low"
               WHEN MSRP <=600 AND MSRP >= 300 THEN "Mid"
               ELSE "High" END AS price_tier,
               round(value/MSRP, 2) as discount_percentage
               FROM data')

#split data into operators to build out predictions further if needed.
ATT <- sqldf('SELECT Year, week_num, Operator, price_tier, Manufacturer, SUM(quantity) as quantity
               FROM data
               WHERE Operator = "AT&T"
               GROUP BY 1,2,3,4,5')
VZW <- sqldf('SELECT Year, week_num, Operator, price_tier, Manufacturer, SUM(quantity) as quantity
               FROM data
             WHERE Operator = "Verizon"
             GROUP BY 1,2,3,4,5')
TMO <- sqldf('SELECT Year, week_num, Operator, price_tier, Manufacturer, SUM(quantity) as quantity
               FROM data
             WHERE Operator = "T-Mobile"
             GROUP BY 1,2,3,4,5')
SPR <- sqldf('SELECT Year, week_num, Operator, price_tier, Manufacturer, SUM(quantity) as quantity
               FROM data
             WHERE Operator = "Sprint"
             GROUP BY 1,2,3,4,5')
TOT <- sqldf('SELECT Year, week_num, Operator, price_tier, Manufacturer, discount_percentage, SUM(quantity) as quantity
               FROM data
             GROUP BY 1,2,3,4,5')

#consolidate all into a single data frame.
univariate <- sqldf('SELECT
               a.Year,
               a.week_num,
               a.price_tier,
               SUM(a.quantity) as tot_qty,
               SUM(b.quantity) as att_qty,
               SUM(c.quantity) as spr_qty,
               SUM(d.quantity) as tmo_qty,
               SUM(e.quantity) as vzw_qty
               FROM TOT a
               JOIN ATT b
               ON a.Year = b.Year AND a.week_num = b.week_num AND a.price_tier = b.price_tier
               JOIN TMO c
               ON a.Year = c.Year AND a.week_num = c.week_num AND a.price_tier = c.price_tier
               JOIN SPR d
               ON a.Year = d.Year AND a.week_num = d.week_num AND a.price_tier = d.price_tier
               JOIN VZW e
               ON a.Year = e.Year AND a.week_num = e.week_num AND a.price_tier = e.price_tier
               WHERE a.Year >= 2015
               GROUP BY 1,2,3')

#break data frame into low, mid, and high data frames.  Also split into train and test, 2019 will be used to test the prediction.
univariate_low <- sqldf('SELECT Year, week_num, tot_qty, att_qty, spr_qty, tmo_qty, vzw_qty
                        FROM univariate
                        WHERE price_tier = "Low"')

univariate_low_train <- sqldf('SELECT Year, week_num, tot_qty, att_qty, spr_qty, tmo_qty, vzw_qty
                        FROM univariate
                              WHERE price_tier = "Low"
                              AND Year < 2019')

univariate_mid <- sqldf('SELECT Year, week_num, tot_qty, att_qty, spr_qty, tmo_qty, vzw_qty
                        FROM univariate
                        WHERE price_tier = "Mid"')

univariate_mid_train <- sqldf('SELECT Year, week_num, tot_qty, att_qty, spr_qty, tmo_qty, vzw_qty
                        FROM univariate
                        WHERE price_tier = "Mid"
                        AND Year < 2019')

univariate_high <- sqldf('SELECT Year, week_num, tot_qty, att_qty, spr_qty, tmo_qty, vzw_qty
                        FROM univariate
                        WHERE price_tier = "High"')

univariate_high_train <- sqldf('SELECT Year, week_num, tot_qty, att_qty, spr_qty, tmo_qty, vzw_qty
                        FROM univariate
                        WHERE price_tier = "High"
                        AND Year < 2019')

univariate_tot_train <- sqldf('SELECT Year, week_num, SUM(tot_qty) as tot_qty, SUM(att_qty) as att_qty, SUM(spr_qty) as spr_qty, SUM(tmo_qty) as tmo_qty, SUM(vzw_qty) as vzw_qty
                        FROM univariate
                        WHERE Year < 2019
                        GROUP BY 1,2')

univariate_tot <- sqldf('SELECT Year, week_num, SUM(tot_qty) as tot_qty, SUM(att_qty) as att_qty, SUM(spr_qty) as spr_qty, SUM(tmo_qty) as tmo_qty, SUM(vzw_qty) as vzw_qty
                        FROM univariate
                        GROUP BY 1,2')

#we can try to rework the univariiate data frame with promotional data
multivariate <- sqldf('SELECT
                      a.Year,
                      a.week_num,
                      a.price_tier,
                      a.discount_percentage,
                      SUM(a.quantity) as tot_qty,
                      SUM(b.quantity) as att_qty,
                      SUM(c.quantity) as spr_qty,
                      SUM(d.quantity) as tmo_qty,
                      SUM(e.quantity) as vzw_qty
                      FROM TOT a
                      JOIN ATT b
                      ON a.Year = b.Year AND a.week_num = b.week_num AND a.price_tier = b.price_tier
                      JOIN TMO c
                      ON a.Year = c.Year AND a.week_num = c.week_num AND a.price_tier = c.price_tier
                      JOIN SPR d
                      ON a.Year = d.Year AND a.week_num = d.week_num AND a.price_tier = d.price_tier
                      JOIN VZW e
                      ON a.Year = e.Year AND a.week_num = e.week_num AND a.price_tier = e.price_tier
                      WHERE a.Year >= 2015
                      GROUP BY 1,2,3,4')

#replace NA with 0 to correct errors in promo value calculation
multivariate[is.na(multivariate)] <- 0

#could not run xreg as parameter since promotion value tracks back until the beginning of 2018, which is not enough data for the data to come clost to a normal distribution.
correlation <- subset(multivariate, Year >= 2018)
correlation <- correlation[,4:9]
chart.Correlation(correlation[sapply(correlation, function(x) !is.factor(x))])

#review data distribution
hist(univariate_tot$tot_qty) 
#data is not normal and failed shapiro test.
shapiro.test(univariate_tot$tot_qty)

#log data and retest for normality
univariate_tot_log <- log(univariate_tot$tot_qty)
hist(univariate_tot_log)

#data still failed test of normality, will try to proceed with holt winters even though shapiro test failed.
shapiro.test(univariate_tot_log)

#lets see if pricing tiers will pass the shapiro test
hist(univariate_high_train$tot_qty) 
#data is not normal and failed shapiro test.
shapiro.test(univariate_high_train$tot_qty)

#log data and retest for normality
univariate_high_log <- log(univariate_high_train$tot_qty)
hist(univariate_high_log)
#even after transforming the data the results are highly skewed and not normal proceeding to the mid tier 
shapiro.test(univariate_high_log)

#mid tier dat normality test
hist(univariate_mid_train$tot_qty) 
#data is not normal and failed shapiro test.
shapiro.test(univariate_mid_train$tot_qty)

#log data and retest for normality
univariate_mid_log <- log(univariate_mid_train$tot_qty)
hist(univariate_mid_log)
#data also is not normal and fails shapiro test.
shapiro.test(univariate_mid_log)

#proceeding using the tot_qty data frame.  Timeseries, data starts on week 2 in most cases and goes to week 53.
tot_sales_act <- ts(univariate_tot[,3], frequency = 53, start = c(2015, 2), end = c(2019,38))
tot_sales <- ts(log(univariate_tot_train[,3]), frequency = 53, start = c(2015, 2), end = c(2018,52))
plot(ts(tot_sales))
plot.ts(SMA(tot_sales, n=10))                
decomp <- decompose(tot_sales) 
plot(decomp)

#create holt winters prediction
tot_sales_hw <- HoltWinters(tot_sales)
summary(tot_sales_hw)
plot(tot_sales_hw)
#forecast for the next 38 weeks in 2019 (lambda = 0 reverses the log transformation)
tot_sales_hw_forecast <- forecast(tot_sales_hw, h=38, lambda = 0)
plot(tot_sales_hw_forecast)
#model performed much better than expected, all values fall within the 5% confidence interval.
lines(tot_sales_act, col='red')

#the ARIMA model performs ok but slightly worse than the Holt Winters.
tot_sales_arima <- auto.arima(tot_sales, D=1)
tot_sales_arima_forecast <- forecast(tot_sales_arima, h=38, lambda = 0)
plot(tot_sales_arima_forecast)
lines(tot_sales_act, col='red')

#Univariate modeling worked better than expected with slight variations that could not be answered with just historical values alone.
