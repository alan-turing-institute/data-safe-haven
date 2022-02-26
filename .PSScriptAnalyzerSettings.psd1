@{
    Severity     = "Information"
    ExcludeRules = @(
        # Ignore error when using 'ConvertTo-SecureString' with '-AsPlainText'
        # and a string argument rather than an encrypted string
        "PSAvoidUsingConvertToSecureStringWithPlainText",
        # Ignore error when a function has both 'Username' and 'Password'
        # arguments
        "PSAvoidUsingUsernameAndPasswordParams",
        # Ignore DSC errors as we want to phase out opaque DSC calls
        "PSDSCDscTestsPresent",
        "PSDSCDscExamplesPresent",
        "PSDSCUseVerboseMessageInDSCResource",
        # TODO: stop ignoring these
        "PSAvoidUsingPositionalParameters",
        "PSProvideCommentHelp",
        "PSUseOutputTypeCorrectly"
    )
}
