using Pkg

# Get the list of packages to check
missing_packages = String[]
packages = readlines(joinpath("..", "package_lists", "packages-julia.list"))
println("Testing ", size(packages, 1), " Julia packages")

# Redirect stdout to suppress package building messages
original_stdout = stdout
(rd, wr) = redirect_stdout();

# Check for packages in two ways
for packageName in readlines(joinpath("..", "package_lists", "packages-julia.list"))
    # Check that the package exists
    try
        Pkg.status(packageName)
    catch
        push!(missing_packages, packageName)
    end
    # Check that the package is usable (NB. this can be slow)
    try
        package = Symbol(packageName)
        @eval using $package
    catch
        push!(missing_packages, packageName)
    end
end

# Return to original stdout
redirect_stdout(original_stdout)

# Print a summary of the package tests
if isempty(missing_packages)
    println("All ", size(packages)[1], " packages are installed")
else
    println("Packages not installed: ", Set(missing_packages))
end
