dotenv = require('dotenv')
async = require('async')
request = require('request')
Firebase = require('firebase')
_ = require('lodash')

# This function creates contracts via Signable (https://app.signable.co.uk).
# It consumes data from Kinesis events, pushes the data to the Signable API,
# and then it stores the contract envelope's fingerpint in Firebase.

# Store sensitive variables in an environment file outside of source control.
dotenv.load()

# Keep all our hard-coded values in one place.
settings =
  host: 'https://api.signable.co.uk/v1/'
  path: 'envelopes'
  apiUserId: 9468
  templateFingerprint: 'c42f0ce06c790ca21ee4399f62e08b0e'
  templateSignerId: 838930
  redirectUrl: 'https://www.hillgateconnect.com'
  hillgateSigner:
    id: 838931
    name: 'Hillgate'
    email: 'chahna@hillgateconnect.com'
    message: 'Please sign on behalf of Hillgate'

# Extract data from the kinesis event
exports.handler = (event, context) ->

  # This function abstracts the expected structure of any Kinesis payload,
  # which is a base64-encoded string of a JSON object, passing the data to
  # a private function.
  handlePayload = (record, callback) ->
    encodedPayload = record.kinesis.data
    rawPayload = new Buffer(encodedPayload, 'base64').toString('utf-8')
    handleData JSON.parse(rawPayload), callback

  # The Kinesis event may contain multiple records in a specific order.
  # Since our handlers are asynchronous, we handle each payload in series,
  # calling the parent handler's callback (context.done) upon completion.
  async.eachSeries event.Records, handlePayload, context.done

# This is how we do it…
handleData = (data, callback) ->

  contractRefUrl = "#{process.env.FIREBASE_URL}contracts/#{data.contractId}"
  contractRef = new Firebase(contractRefUrl)

  contractRef.on 'value', (snapshot) ->
    createSignableEnvelope snapshot.val(), (err, fingerprint) ->
      contractRef
        .child('company')
        .update {envelopeFingerprint: fingerprint}, callback

createSignableEnvelope = (snapshotVal, callback) ->
  options =
    uri: settings.host + settings.path
    method: 'POST'
    form: buildObjectToPost(snapshotVal)
    auth:
      user: process.env.SIGNABLE_API_KEY
      password: 'x'

  request options, (error, response, body) ->
    if error
      callback(error, null)
    else
      callback(null, JSON.parse(body).envelope_fingerprint)

buildObjectToPost = (snapshotVal) ->
  docs = [
    document_title: getDocumentTitle(snapshotVal)
    document_template_fingerprint: settings.templateFingerprint
    document_merge_fields: [
      {field_id: 1373833, field_value: snapshotVal.project.name}
      {field_id: 1373835, field_value: snapshotVal.company.name}
      {field_id: 1373836, field_value: snapshotVal.consultant.name}
      {field_id: 1373837, field_value: snapshotVal.consultant.name}
      {field_id: 1373839, field_value: snapshotVal.project.startDate}
      {field_id: 1373840, field_value: snapshotVal.project.endDate}
      {field_id: 1373838, field_value: snapshotVal.company.userName}
      {field_id: 1373851, field_value: snapshotVal.project.scope}
      {field_id: 1373850, field_value: snapshotVal.project.deliverables}
    ]
  ]
  parties = [
    party_name: settings.hillgateSigner.name
    party_email: settings.hillgateSigner.email
    party_id: settings.hillgateSigner.id
    party_message: settings.hillgateSigner.message
  ,
    party_name: snapshotVal.company.name
    party_email: snapshotVal.company.email
    party_id: settings.templateSignerId
    party_message: getMessage(snapshotVal)
  ]

  envelope_title: getDocumentTitle(snapshotVal)
  user_id: settings.apiUserId
  envelope_redirect_url: settings.redirectUrl
  envelope_documents: JSON.stringify(docs)
  envelope_parties: JSON.stringify(parties)

getDocumentTitle = (snapshotVal) ->
  "#{snapshotVal.company.name}: #{snapshotVal.project.name}"

getMessage = (snapshotVal) ->
  "Please sign on behalf of #{snapshotVal.company.name}"

# handleData contractId: 112358, _.noop
