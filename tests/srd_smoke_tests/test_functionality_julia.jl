using LinearAlgebra, StatsFuns, Optim, Distributions, Formatting

# test random numbers, Distributions
X = randn(1000, 10)
w = randn(10)
y = rand.(Bernoulli.(logistic.(X * w))) * 1.0

# test linear algebra
svd(X)

# test optimization
epsilon = eps()
function logistic_regression_loss(w)
    p = logistic.(X * w)
    return -mean(y .* log.(p .+ epsilon) + (1 .- y) .* log.(1 .- p .+ epsilon))
end

true_loss = logistic_regression_loss(w)
optim_soln = optimize(logistic_regression_loss, zeros(10), BFGS())

# test formatting
delta = format("{:.4f}", true_loss - optim_soln.minimum)

# (warning if optimizer performs poorly)
if true_loss < optim_soln.minimum
    @warn "Optim found suboptimal solution by " * delta
end

println("All functionality tests passed")
