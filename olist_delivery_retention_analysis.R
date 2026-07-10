# 1. Libraries

library(tidyverse)
library(lubridate)
library(scales)

# 2. Data loading (relative paths)
data_dir = "Dataset"

customers  = read_csv(file.path(data_dir, "olist_customers_dataset.csv"))
orders     = read_csv(file.path(data_dir, "olist_orders_dataset.csv"))
order_items= read_csv(file.path(data_dir, "olist_order_items_dataset.csv"))
reviews    = read_csv(file.path(data_dir, "olist_order_reviews_dataset.csv"))
products   = read_csv(file.path(data_dir, "olist_products_dataset.csv"))
categories = read_csv(file.path(data_dir, "product_category_name_translation.csv"))

# 3. Quick inspection (types + structure)
glimpse(customers)
glimpse(orders)
glimpse(order_items)
glimpse(reviews)
glimpse(products)
glimpse(categories)


# 4. Missing values
anyNA(orders)
sort(colSums(is.na(orders)), decreasing = TRUE)[1:10]

anyNA(reviews)
sort(colSums(is.na(reviews)), decreasing = TRUE)[1:10]

anyNA(order_items)
sort(colSums(is.na(order_items)), decreasing = TRUE)[1:10]

anyNA(products)
sort(colSums(is.na(products)), decreasing = TRUE)[1:10]

anyNA(customers)
sort(colSums(is.na(customers)), decreasing = TRUE)[1:10]

# 5. DELIVERY PERFORMANCE
# Research Question: How often are orders delivered late, and by how many days?

# 5.1 Ensure timestamps are datetime (only convert if needed)

datetime_cols = c("order_purchase_timestamp",
                  "order_delivered_customer_date",
                  "order_estimated_delivery_date")

orders = orders %>%
  mutate(across(all_of(datetime_cols), ~ {
    if (inherits(.x, "POSIXct") || inherits(.x, "POSIXt")) {
      .x
    } else {
      as.POSIXct(.x, format = "%Y-%m-%d %H:%M:%S", tz = "UTC")
    }
  }))

# 5.2 Keep delivered orders with valid delivery + estimate dates
# (report missing values before dropping them)
delivered_total = orders %>%
  filter(order_status == "delivered") %>%
  nrow()

missing_delivery_dates = orders %>%
  filter(order_status == "delivered") %>%
  summarise(
    missing_delivered_customer_date = sum(is.na(order_delivered_customer_date)),
    missing_estimated_delivery_date = sum(is.na(order_estimated_delivery_date)))
print(missing_delivery_dates)

orders_delivered_clean = orders %>%
  filter(order_status == "delivered") %>%
  drop_na(order_delivered_customer_date, order_estimated_delivery_date)
delivered_clean_total = nrow(orders_delivered_clean)

delivery_cleaning_summary = tibble(
  metric = c("Delivered orders (raw)", "Delivered orders after dropping missing dates", "Share retained"),
  value = c(delivered_total, delivered_clean_total, round(delivered_clean_total / delivered_total, 4)))
print(delivery_cleaning_summary)

# Compute delivery delay and delivery status AFTER cleaning
orders_delivered = orders_delivered_clean %>%
  mutate(
    delivery_delay_days = as.integer(difftime(order_delivered_customer_date,
                                              order_estimated_delivery_date,
                                              units = "days")),
    late_delivery = ifelse(delivery_delay_days > 0, "Late", "On time or early"))

# 5.3 Figure 1: Distribution of delivery delay
ggplot(orders_delivered, aes(x = delivery_delay_days)) +
  geom_histogram(bins = 60, fill = "blue", alpha = 0.80, color = "white") +
  coord_cartesian(xlim = c(-30, 30)) +
  labs(title = "Distribution of Delivery Delay",
    subtitle = "Zoomed to -30 to +30 days for readability",
    x = "Delivery delay (days)",
    y = "Number of orders") +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold", hjust = 0.5),
    plot.subtitle = element_text(hjust = 0.5))

# 5.4 Figure 2: Share of late vs on-time/early deliveries
delay_share = orders_delivered %>%
  count(late_delivery) %>%
  mutate(share = n / sum(n))

ggplot(delay_share, aes(x = late_delivery, y = share, fill = late_delivery)) +
  geom_col(width = 0.45, alpha = 0.80) +
  geom_text(aes(label = percent(share, accuracy = 0.1)),
            vjust = -0.4, size = 4) +
  scale_y_continuous(limits = c(0, 1), labels = percent_format(accuracy = 1)) +
  scale_fill_manual(values = c("Late" = "firebrick", "On time or early" = "steelblue")) +
  labs(title = "Share of Late vs On-time/Early Deliveries",
    x = "Delivery status",
    y = "Share of delivered orders") +
  theme_minimal() +
  theme(legend.position = "none",
    plot.title = element_text(face = "bold", hjust = 0.5))

# 6. REVIEWS & DELIVERY STATUS
# Research Question: Do late deliveries lead to lower review scores?

# 6.1 Clean review scores
reviews_clean = reviews %>%
  select(order_id, review_score) %>%
  distinct(order_id, .keep_all = TRUE)

# Add reviews to Orders delivered data set
orders_reviews = orders_delivered %>%
  left_join(reviews_clean, by = "order_id")

# Review availability summary (How many delivered orders lack a review score)
review_availability = orders_reviews %>%
  summarise(
    delivered_orders = n(),
    with_review = sum(!is.na(review_score)),
    without_review = sum(is.na(review_score)),
    share_with_review = round(with_review / delivered_orders, 4))

print(review_availability)


# Keeping only orders with a review score
orders_reviews_scored = orders_reviews %>%
  drop_na(review_score)

# 6.2 Descriptive statistics table

review_stats = orders_reviews_scored %>%
  group_by(late_delivery) %>%
  summarise(n_orders = n(),
    mean_review = mean(review_score),
    median_review = median(review_score),
    sd_review = sd(review_score),
    .groups = "drop")
print(review_stats)

# 6.3 Figure 3: Review score distribution (boxplot)

ggplot(orders_reviews_scored,
       aes(x = late_delivery, y = review_score, fill = late_delivery)) +
  geom_boxplot(width = 0.55, alpha = 0.85, outlier.alpha = 0.25) +
  scale_fill_manual(values = c("Late" = "firebrick", "On time or early" = "steelblue")) +
  scale_y_continuous(breaks = 1:5, limits = c(1, 5)) +
  labs(
    title = "Customer Review Scores: Late vs On-time/Early Deliveries",
    subtitle = "Late deliveries are associated with much lower scores",
    x = "Delivery status",
    y = "Review score (1 = worst, 5 = best)") +
  theme_minimal() +
  theme(
    legend.position = "none",
    plot.title = element_text(face = "bold", hjust = 0.5),
    plot.subtitle = element_text(hjust = 0.5))

# 6.4 Statistical tests (Wilcoxon + Chi-square)
# Wilcoxon rank-sum: appropriate for ordinal review scores
wilcox_result = wilcox.test(review_score ~ late_delivery, data = orders_reviews_scored)
print(wilcox_result)

# Chi-square: convert reviews into Low (1-3) vs High (4-5)
orders_reviews_scored = orders_reviews_scored %>%
  mutate(low_review = ifelse(review_score <= 3, "Low (1-3)", "High (4-5)"))
chi_table = table(orders_reviews_scored$late_delivery, orders_reviews_scored$low_review)
print(chi_table)
chi_result = chisq.test(chi_table)
print(chi_result)


# 7. REPEAT PURCHASE RETENTION
# Research Question: Are customers with a late first delivery less likely to buy again?
# Attach unique customer identifier
orders_delivered_cust = orders_delivered %>%
  left_join(customers %>% select(customer_id, customer_unique_id), by = "customer_id")

# Count delivered orders per customer and define repeat customer (>= 2)
customer_order_counts = orders_delivered_cust %>%
  group_by(customer_unique_id) %>%
  summarise(
    delivered_orders = n(),
    repeat_customer = ifelse(delivered_orders >= 2, 1, 0),
    .groups = "drop")

# First delivered order per customer (defines first experience)
first_order = orders_delivered_cust %>%
  arrange(customer_unique_id, order_purchase_timestamp) %>%
  group_by(customer_unique_id) %>%
  slice(1) %>%
  ungroup() %>%
  select(customer_unique_id, first_late_delivery = late_delivery)

repeat_analysis = first_order %>%
  left_join(customer_order_counts, by = "customer_unique_id")

repeat_rate_by_experience = repeat_analysis %>%
  group_by(first_late_delivery) %>%
  summarise(
    customers = n(),
    repeat_customers = sum(repeat_customer),
    repeat_rate = mean(repeat_customer),
    .groups = "drop")

print(repeat_rate_by_experience)

# Chi-square test on repeat purchase vs first delivery experience
repeat_table = table(repeat_analysis$first_late_delivery, repeat_analysis$repeat_customer)
print(repeat_table)
print(chisq.test(repeat_table))

# Figure 4: Repeat purchase rate plot (zoomed)
ggplot(repeat_rate_by_experience,
       aes(x = first_late_delivery, y = repeat_rate, fill = first_late_delivery)) +
  geom_col(width = 0.45, alpha = 0.85) +
  geom_text(aes(label = percent(repeat_rate, accuracy = 0.1)),
            vjust = -0.4, size = 4) +
  scale_y_continuous(labels = percent_format(accuracy = 1)) +
  coord_cartesian(ylim = c(0, 0.25)) +
  scale_fill_manual(values = c("Late" = "firebrick", "On time or early" = "steelblue")) +
  labs(
    title = "Repeat Purchase Rate by First Delivery Experience",
    x = "Delivery status of first delivered order",
    y = "Repeat purchase rate") +
  theme_minimal() +
  theme(legend.position = "none",
    plot.title = element_text(face = "bold", hjust = 0.5))

# 8. REVENUE RETENTION (COHORT)
# Research Question: How does revenue evolve after the first purchase month?

# 8.1 Revenue per order (sum of item prices)
order_revenue = order_items %>%
  group_by(order_id) %>%
  summarise(order_revenue = sum(price, na.rm = TRUE), .groups = "drop")

# 8.2 Create customer-month dataset + cohort month
orders_rev = orders_delivered %>%
  left_join(order_revenue, by = "order_id") %>%
  left_join(customers %>% select(customer_id, customer_unique_id), by = "customer_id") %>%
  mutate(order_month = floor_date(order_purchase_timestamp, unit = "month")) %>%
  group_by(customer_unique_id) %>%
  mutate(cohort_month = min(order_month)) %>%
  ungroup() %>%
  mutate(months_since_cohort =
      (year(order_month) - year(cohort_month)) * 12 +
      (month(order_month) - month(cohort_month)))

# 8.3 Cohort revenue table
cohort_revenue = orders_rev %>%
  group_by(cohort_month, months_since_cohort) %>%
  summarise(revenue = sum(order_revenue, na.rm = TRUE), .groups = "drop")

# 8.4 Normalize by month 0 to get revenue retention
cohort_month0 = cohort_revenue %>%
  filter(months_since_cohort == 0) %>%
  select(cohort_month, revenue_month0 = revenue)

cohort_revenue_retention = cohort_revenue %>%
  left_join(cohort_month0, by = "cohort_month") %>%
  mutate(revenue_retention = revenue / revenue_month0)
# Average revenue retention by month
avg_cohort_retention = cohort_revenue_retention %>%
  group_by(months_since_cohort) %>%
  summarise(avg_retention = mean(revenue_retention, na.rm = TRUE),
    .groups = "drop") %>%
  filter(months_since_cohort %in% c(0, 1, 3, 6, 9, 12))

# 9. CATEGORY BREAKDOWN
# Research Question: Which categories generate the most revenue, and how do late rates/reviews vary?
# Map product categories to English names
products_cat = products %>%
  left_join(categories, by = "product_category_name") %>%
  mutate(product_category_name_english =
           ifelse(is.na(product_category_name_english), "unknown", product_category_name_english)) %>%
  select(product_id, product_category_name_english)

# Add category to each order item
items_with_cat = order_items %>%
  left_join(products_cat, by = "product_id")

# Revenue per order_id and category
order_category_revenue = items_with_cat %>%
  group_by(order_id, product_category_name_english) %>%
  summarise(category_revenue = sum(price, na.rm = TRUE), .groups = "drop")

# Attach delivery status and review score
category_analysis = order_category_revenue %>%
  left_join(orders_reviews_scored %>% select(order_id, late_delivery, review_score),
            by = "order_id")

category_kpis = category_analysis %>%
  group_by(product_category_name_english) %>%
  summarise(
    orders_in_category = n_distinct(order_id),
    revenue_in_category = sum(category_revenue, na.rm = TRUE),
    late_rate = mean(late_delivery == "Late", na.rm = TRUE),
    mean_review = mean(review_score, na.rm = TRUE),
    .groups = "drop") %>%
  arrange(desc(revenue_in_category))

top_categories_kpis = category_kpis %>% slice(1:10)
print(top_categories_kpis)

# Figure 6: Top categories by revenue
ggplot(top_categories_kpis,
       aes(x = reorder(product_category_name_english, revenue_in_category),
           y = revenue_in_category)) +
  geom_col(fill = "steelblue", alpha = 0.85, width = 0.65) +
  coord_flip() +
  geom_text(
    aes(label = paste0("Late: ", percent(late_rate, accuracy = 1),
                       " | Avg review: ", round(mean_review, 2))),
    hjust = -0.05, size = 3.3) +
  scale_y_continuous(labels = comma_format(),
                     expand = expansion(mult = c(0, 0.58))) +
  labs(
    title = "Revenue Concentration Across Product Categories",
    subtitle = "Revenue based on sum of item prices",
    x = "Product category",
    y = "Revenue") +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold", hjust = 0.5),
    plot.subtitle = element_text(hjust = 0.5))
