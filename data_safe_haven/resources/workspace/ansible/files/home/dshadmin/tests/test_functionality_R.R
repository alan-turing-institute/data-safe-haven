# Test logistic regression using R
library('MASS', lib.loc='~/.local/bats-r-environment')
library('stats')

gen_data <- function(n = 100, p = 3) {
    set.seed(1)
    weights <- stats::rgamma(n = n, shape = rep(1, n), rate = rep(1, n))
    y <- stats::rbinom(n = n, size = 1, prob = 0.5)
    theta <- stats::rnorm(n = p, mean = 0, sd = 1)
    means <- colMeans(as.matrix(y) %*% theta)
    x <- MASS::mvrnorm(n = n, means, diag(1, p, p))
    return(list(x = x, y = y, weights = weights, theta = theta))
}

run_logistic_regression <- function(data) {
    fit <- stats::glm.fit(x = data$x,
                          y = data$y,
                          weights = data$weights,
                          family = stats::quasibinomial(link = "logit"))
    return(fit$coefficients)
}

data <- gen_data()
theta <- run_logistic_regression(data)
print("Logistic regression ran OK")


# Test clustering of random data using R
num_clusters <- 5
N <- 10
set.seed(0, kind = "Mersenne-Twister")
cluster_means <- runif(num_clusters, 0, 10)
means_selector <- as.integer(runif(N, 1, num_clusters + 1))
data_means <- cluster_means[means_selector]
data <- rnorm(n = N, mean = data_means, sd = 0.5)
hc <- hclust(dist(data))
print("Clustering ran OK")

print("All functionality tests passed")
