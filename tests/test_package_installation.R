
# Initialise lists
warning_list <- c()
error_list <- c()

#' Test package with non-standard evaluation and append to the proper list
test_package <- function(p) {
  tryCatch(
    eval(parse(text = paste0("library(", p, ")"))),
    error = function(m) {
      assign("error_list", c(error_list, p), envir = .GlobalEnv)
    },
    warning = function(m) {
      assign("warning_list", c(warning_list, p), envir = .GlobalEnv)
    },
    message = function(m) {
      # do nothing, as many packages print messages upon loading
    })
}

# Read in the package list from the repo
package_list <- scan("../new_dsg_environment/azure-vms/package_lists/cran.list", what="", sep="\n")

# Test each package
for (p in package_list) {
  test_package(p)
}

# Show results
if (0 == length(warning_list) & 0 == length(error_list)) {
  print("All OK!")
} else {

  if (0 < length(warning_list)) {
    print("The following packages gave a warning:")
    print(paste(warning_list, sep = "\n"))
  }

  if (0 < length(error_list)) {
    print("The following packages gave an error:")
    print(paste(error_list, sep = "\n"))
  }
}
