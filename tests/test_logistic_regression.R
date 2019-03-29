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
    
run_logistic_regression <- function() {
  data <- gen_data()
  fit <- stats::glm.fit(x = data$x,
                        y = data$y,
                        weights = data$weights,
                        family = stats::quasibinomial(link = "logit"))
  return(fit$coefficients)
}

theta <- run_logistic_regression()

print("Logistic regression ran OK")
