gulp = require('gulp')
gutil = require('gulp-util')
del = require('del')
coffee = require('gulp-coffee')
rename = require('gulp-rename')
install = require('gulp-install')
zip = require('gulp-zip')
AWS = require('aws-sdk')
fs = require('fs')
runSequence = require('run-sequence')

# First we need to clean out the dist folder and remove the compiled zip file.
gulp.task 'clean', (cb) ->
  del './dist', del('./dist.zip', cb)

# The js task could be replaced with gulp-coffee as desired.
gulp.task 'js', ->
  gulp.src('index.coffee')
    .pipe(coffee())
    .pipe(gulp.dest('dist/'))

# Here we want to install npm packages to dist, ignoring devDependencies.
gulp.task 'npm', ->
  gulp.src('./package.json')
    .pipe(gulp.dest('./dist/'))
    .pipe(install(production: true))

# Next copy over environment variables managed outside of source control.
gulp.task 'env', ->
  gulp.src('./config.env.production')
    .pipe(rename('.env'))
    .pipe(gulp.dest('./dist'))

# Now the dist directory is ready to go. Zip it.
gulp.task 'zip', ->
  gulp.src([
    'dist/**/*'
    '!dist/package.json'
    'dist/.*'
  ]).pipe(zip('dist.zip'))
    .pipe(gulp.dest('./'))

# Per the gulp guidelines, we do not need a plugin for something that can be
# done easily with an existing node module. #CodeOverConfig
#
# Note: This presumes that AWS.config already has credentials. This will be
# the case if you have installed and configured the AWS CLI.
#
# See http://aws.amazon.com/sdk-for-node-js/
gulp.task 'upload', ->
  # TODO: This should probably pull from package.json
  AWS.config.region = 'us-east-1'
  lambda = new (AWS.Lambda)
  functionName = 'video-events'
  lambda.getFunction { FunctionName: functionName }, (err, data) ->
    `var warning`
    if err
      if err.statusCode == 404
        warning = 'Unable to find lambda function ' + deploy_function + '. '
        warning += 'Verify the lambda function name and AWS region are correct.'
        gutil.log warning
      else
        warning = 'AWS API request failed. '
        warning += 'Check your AWS credentials and permissions.'
        gutil.log warning

    # This is a bit silly, simply because these five parameters are required.
    current = data.Configuration
    params =
      FunctionName: functionName
      Handler: current.Handler
      Mode: current.Mode
      Role: current.Role
      Runtime: current.Runtime
    fs.readFile './dist.zip', (err, data) ->
      params['FunctionZip'] = data
      lambda.uploadFunction params, (err, data) ->
        `var warning`
        if err
          warning = 'Package upload failed. '
          warning += 'Check your iam:PassRole permissions.'
          gutil.log warning

# The key to deploying as a single command is to manage the sequence of events.
gulp.task 'default', (callback) ->
  runSequence [ 'clean' ], [
    'js'
    'npm'
    'env'
  ], [ 'zip' ], [ 'upload' ], callback
