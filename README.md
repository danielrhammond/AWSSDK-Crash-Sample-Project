# Explanation

This is a sample project that demonstrates a crash possible in the AWS iOS SDK.

The case demonstrated is when an S3 upload is retried after failing and the file being uploaded (the body of the request) has been deleted since the initial request.

# Build Instructions

1. `pod install`
2. `open AWSS3UploadCrash.xcworkspace`
3. Build & Run
