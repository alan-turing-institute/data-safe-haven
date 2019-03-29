library('MASS')
library('stats')
    
gen_data <- function(n=100, p=3) {
  
  set.seed(1)  
  weights <- stats::rgamma(n=n, shape=rep(1, n), rate=rep(1, n))
  y <- stats::rbinom(n=n, size=1, prob=0.5)
  theta <- stats::rnorm(n=p, mean=0, sd=1)
  means <- colMeans(as.matrix(y) %*% theta)
  x <- MASS::mvrnorm(n=n, means, diag(1, p, p))
  
  return(list(x=x, y=y, weights=weights, theta=theta))  
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

# Also write to a file for pandas to read from
df  <- data.frame(cbind(data$x, data$y))
xnames <- function(i) {
  paste0("x", i)
}
p <- dim(data$x)[2]
names(df) <- c(lapply(seq(1, p), xnames), "y")
write.csv(df, file = "logistic.csv", row.names=F)
