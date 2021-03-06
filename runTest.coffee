fs = require 'fs'
Mocha = require 'mocha'
path = require 'path'

module.exports = (args) ->
  {setup, inicializePo} = require 'test-stack-harness'
  if args.reporter is 'elastic'
    reporter = require './node_modules/test-stack-reporter'
    reporter.send { harness: 'initialization' }

  dependencies = setup args

  safelyExitWebdriver = (cb) ->
    dependencies.exit dependencies.client, cb

  process.on 'uncaughtException', (err) ->
    safelyExitWebdriver ->
      console.error (new Date).toUTCString() + ' uncaughtException:', err.message
      console.error err.stack
      process.exit 1

  require('./libs/findTestCase').find args.runBy, (testCases, tags) ->
    if testCases.length is 0
      console.log 'Test case has not found.'
      process.exit 0

    reporter.send { harness: 'setTags', tags: tags } if args.reporter is 'elastic'

    dependencies.client.init (clientErr) ->
      dependencies.client.session (sessionclientErr, sessionRes) ->
        mocha = new Mocha
          ui: "bdd"
          reporter: if args.reporter is 'elastic' then reporter.reporter else args.reporter
          compilers: "coffee:coffee-script/register"
          require: "coffee-script/register"
          timeout: args.timeout
          bail: if args.bail then yes else no

        mocha.addFile tc for tc in testCases if testCases.length != 0

        mocha.suite.on 'pre-require', (context) ->

          if args.list isnt undefined
            dependencies['list'] = {}
            for item in args.list
              item = item.split '='
              dependencies.list[item[0]] = item[1]

          context.client = dependencies.client
          context.dependencies = dependencies
          context[k] = v for k, v of inicializePo().pageObjects

          if args.reporter is 'elastic'
            reporter.send
              harness: 'webdriverStart'
              sessionId: if !clientErr? then sessionRes.sessionId else null
              err: if clientErr? then clientErr.toString() else null

            if args.list isnt undefined
              reporter.send { harness: 'list', title: item } for item in args.list

        mocha.suite.on 'require', (loadedTest) ->
          suite = loadedTest()
          suite.beforeAll (done) ->
            return done()

        runner = mocha.run (failures) ->
          safelyExitWebdriver ->
            process.on 'exit', ->
              process.exit failures

        runner.on 'fail', ->
          if args.attachments isnt undefined
            screenshot = args.attachments + Date.now() + ".png"
            dependencies.client.saveScreenshot screenshot, (err) ->
              if err
                console.error (new Date).toUTCString() + ' uncaughtException:', err.message
                console.error err.stack
                process.exit 1
              if args.reporter is 'elastic'
                reporter.send
                  harness: 'screenshot'
                  title: screenshot
              else
                console.log "Screenshot saved to #{screenshot}"
