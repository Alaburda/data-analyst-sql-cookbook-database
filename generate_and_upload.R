# Load required libraries
library(DBI)
library(RSQLite)
library(dplyr)
library(lubridate)

# Set seed for reproducibility
set.seed(42) 


# Create a calendar table ----

date_dimension <- tibble(date = seq(as.Date('2011-01-01'),as.Date('2011-01-31'),by = 1),
                         full_date_description = format(date, format="%Y m. %B %d d."),
                         day_of_week = wday(date, label=FALSE, week_start = 1),
                         day_of_week_name = wday(date, label=TRUE, abbr = FALSE),
                         calendar_iso_week = isoweek(date),
                         calendar_week = week(date),
                         calendar_month = month(date),
                         calendar_month_name = month(date, label = TRUE, abbr = FALSE),
                         calendar_quarter = quarter(date),
                         calendar_quarter_name = paste0("Q",quarter(date)),
                         calendar_year = year(date),
                         is_weekday = as.integer(wday(date, week_start = 1) < 6))

get_holidays <- function(country_code = "lt", year = "2023") {
  
  rs <- httr::GET(glue::glue("https://date.nager.at/api/v3/publicholidays/{year}/{country_code}"))
  
  out <- httr::content(rs) %>% 
    tibble::enframe() %>% 
    dplyr::select(value) %>% 
    tidyr::unnest_wider(value) %>% 
    dplyr::transmute(date = as.Date(date),
           holiday_name_local = localName,
           holiday_name = name)
  
  return(out)
  
}

date_dimension <- function(date_from, date_to, full_date_format = "%Y m. %B %d d.", week_start = 1, country_code = "LT") {
  
  date_skeleton <- tibble(date = seq(as.Date(date_from),as.Date(date_to),by = 1),
                          full_date_description = format(date, format=full_date_format),
                          day_of_week = wday(date, label=FALSE, week_start = week_start),
                          day_of_week_name = wday(date, label=TRUE, abbr = FALSE),
                          calendar_iso_week = isoweek(date),
                          calendar_week = week(date),
                          calendar_month = month(date),
                          calendar_month_name = month(date, label = TRUE, abbr = FALSE),
                          calendar_quarter = quarter(date),
                          calendar_quarter_name = paste0("Q",quarter(date)),
                          calendar_year = year(date),
                          is_weekday = as.integer(wday(date, week_start = 1) < 6))

  holidays <- purrr::map_df(unique(date_skeleton$calendar_year), ~get_holidays(country_code = country_code, year = .))

  out <- date_skeleton %>%
    dplyr::left_join(holidays, by = "date") %>%
    dplyr::mutate(is_workday = is_weekday*is.na(holiday_name))


  return(out)

}

calendar <- date_dimension("2024-01-01","2024-05-01")


# Sample users data (as in your SQL)
users <- data.frame(
  user_id = 1:5,
  first_name = c('Alice', 'Bob', 'Carol', 'David', 'Eve'),
  last_name = c('Smith', 'Johnson', 'Williams', 'Brown', 'Davis'),
  email = c('alice.smith@example.com', 'bob.johnson@example.com', 'carol.williams@example.com', 'david.brown@example.com', 'eve.davis@example.com'),
  signup_date = as.Date(c('2024-01-15', '2024-02-20', '2024-03-05', '2024-04-10', '2024-05-25'))
)

# Generate subscriptions
generate_subscription <- function(user_id, signup_date) {
  start_offset <- sample(0:29, 1)
  duration_months <- sample(1:12, 1)
  start_date <- signup_date + days(start_offset)
  end_date <- start_date %m+% months(duration_months)
  data.frame(
    user_id = user_id,
    start_date = start_date,
    duration_months = duration_months,
    end_date = end_date
  )
}

subscriptions <- bind_rows(
  lapply(1:nrow(users), function(i) {
    generate_subscription(users$user_id[i], users$signup_date[i])
  })
)

# Define products (subscription plans)
products <- data.frame(
  product_id = 1:3,
  product_name = c('Basic', 'Standard', 'Premium'),
  monthly_price = c(9.99, 14.99, 24.99)
)

# Employees table with ragged hierarchy (manager_id, CEO has NA)
n_employees <- 20
set.seed(42)
first_names <- c('John', 'Jane', 'Mike', 'Sara', 'Tom', 'Anna', 'Paul', 'Linda', 'Chris', 'Nina', 'Alex', 'Kate', 'Sam', 'Emma', 'Luke', 'Olga', 'Nick', 'Ivy', 'Ben', 'Zoe')
last_names <- c('Doe', 'Smith', 'Brown', 'White', 'Black', 'Green', 'King', 'Lee', 'Young', 'Hall', 'Scott', 'Adams', 'Clark', 'Evans', 'Hill', 'Moore', 'Turner', 'Ward', 'Wood', 'Wright')
departments <- c('Support', 'Technical', 'Billing')
employees <- data.frame(
  employee_id = 1:n_employees,
  first_name = first_names[1:n_employees],
  last_name = last_names[1:n_employees],
  department = sample(departments, n_employees, replace = TRUE),
  manager_id = NA
)
# Assign managers: CEO (1) has NA, next 3 report to CEO, next 6 report to 2-4, rest report to 5-10
employees$manager_id[2:4] <- 1
employees$manager_id[5:10] <- sample(2:4, 6, replace=TRUE)
employees$manager_id[11:20] <- sample(5:10, 10, replace=TRUE)

# Subscription tiers (plans)
subscription_tiers <- data.frame(
  tier_id = 1:3,
  tier_name = c('Basic', 'Standard', 'Premium'),
  monthly_price = c(9.99, 14.99, 24.99)
)

# SCD2 Subscriptions (no overlap per user)
scd2_subscriptions <- bind_rows(
  lapply(1:nrow(users), function(i) {
    n_versions <- sample(1:3, 1)
    start_dates <- sort(users$signup_date[i] + cumsum(sample(30:120, n_versions, replace=TRUE)))
    durations <- sample(1:12, n_versions, replace=TRUE)
    tier_ids <- sample(subscription_tiers$tier_id, n_versions, replace=TRUE)
    end_dates <- c(start_dates[-1] - 1, as.Date('2025-12-31'))
    data.frame(
      subscription_sk = NA,
      user_id = users$user_id[i],
      tier_id = tier_ids,
      start_date = start_dates,
      end_date = end_dates,
      effective_from = start_dates,
      effective_to = c(start_dates[-1] - 1, as.Date('9999-12-31')),
      is_current = c(rep(0, n_versions-1), 1)
    )
  })
)
scd2_subscriptions$subscription_sk <- 1:nrow(scd2_subscriptions)
scd2_subscriptions <- scd2_subscriptions[,c('subscription_sk','user_id','tier_id','start_date','end_date','effective_from','effective_to','is_current')]

# SCD2 Support tickets (can overlap)
support_tickets <- bind_rows(
  lapply(1:nrow(users), function(i) {
    n_tickets <- sample(1:3, 1)
    ticket_starts <- sort(users$signup_date[i] + sample(1:300, n_tickets))
    ticket_ends <- ticket_starts + sample(1:30, n_tickets, replace=TRUE)
    employee_ids <- sample(employees$employee_id, n_tickets, replace=TRUE)
    data.frame(
      ticket_sk = NA,
      user_id = users$user_id[i],
      employee_id = employee_ids,
      subject = sample(c('Billing','Technical','General Inquiry'), n_tickets, replace=TRUE),
      status = sample(c('open','closed','pending'), n_tickets, replace=TRUE),
      effective_from = ticket_starts,
      effective_to = ticket_ends,
      is_current = as.integer(ticket_ends == max(ticket_ends))
    )
  })
)
if (nrow(support_tickets) > 0) support_tickets$ticket_sk <- 1:nrow(support_tickets)
support_tickets <- support_tickets[,c('ticket_sk','user_id','employee_id','subject','status','effective_from','effective_to','is_current')]

# Create and populate SQLite database
db_file <- 'cookbookdb.sqlite'
if (file.exists(db_file)) file.remove(db_file)
con <- dbConnect(RSQLite::SQLite(), db_file)

dbWriteTable(con, 'users', users, row.names = FALSE)
dbWriteTable(con, 'subscription_tiers', subscription_tiers, row.names = FALSE)
dbWriteTable(con, 'subscriptions', scd2_subscriptions, row.names = FALSE)
dbWriteTable(con, 'employees', employees, row.names = FALSE)
dbWriteTable(con, 'support_tickets', support_tickets, row.names = FALSE)
dbWriteTable(con, 'calendar', calendar, row.names = FALSE)


# Test: Print tables
print(dbReadTable(con, 'users'))
print(dbReadTable(con, 'subscription_tiers'))
print(head(dbReadTable(con, 'subscriptions')))
print(dbReadTable(con, 'employees'))
print(head(dbReadTable(con, 'support_tickets')))

dbDisconnect(con)
