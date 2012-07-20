path = require 'path'
fs = require 'fs'

wrench = require 'wrench'

fileUtils = require '../../util/file'
logger = require '../../util/logger'
AbstractCompiler = require '../compiler'

module.exports = class AbstractTemplateCompiler extends AbstractCompiler

  constructor: (config) ->
    super(config, config.compilers.template)
    @templateFileName = path.join(@compDir, @config.outputFileName + ".js")
    if @clientLibrary?
      @mimosaClientLibraryPath = path.join __dirname, "client", "#{@clientLibrary}.js"
      @clientPath = path.join path.dirname(@templateFileName), 'vendor', "#{@clientLibrary}.js"
    @notifyOnSuccess = config.growl.onSuccess.template

  # OVERRIDE THIS
  compile: (fileNames, callback) -> throw new Error "Method compile must be implemented"

  created: =>
    if @startupFinished then @_gatherFiles() else @done()

  updated: =>
    @_gatherFiles()

  removed: =>
    @_gatherFiles(true)

  cleanup: ->
    @_removeClientLibrary()
    @removeTheFile(@templateFileName, false) if fs.existsSync @templateFileName

  doneStartup: ->
    @_gatherFiles()

  _gatherFiles: (isRemove = false) ->
    fileNames = []
    allFiles = wrench.readdirSyncRecursive(@srcDir)
      .map (file) => path.join(@srcDir, file)

    for file in allFiles
      extension = path.extname(file).substring(1)
      fileNames.push(file) if @config.extensions.indexOf(extension) >= 0

    if fileNames.length is 0
      if isRemove
        @removeTheFile(@templateFileName)
        @_removeClientLibrary()
    else
      @_writeClientLibrary()
      if @_templateNeedsCompiling(fileNames)
        @compile(fileNames, @_write)
      else
        @_reportStartupDone()

  _templateNeedsCompiling: (fileNames) ->
    for file in fileNames
      return true if @fileNeedsCompiling(file, @templateFileName)
    false

  _write: (error, output) =>
    if error
      @failed(err)
    else
      @write(@templateFileName, output) if output?

    @_reportStartupDone()

  _reportStartupDone: =>
    unless @startupFinished
      @startupDoneCallback()
      @startupFinished = true

  _removeClientLibrary: ->
    fs.unlink @clientPath if @clientPath? and fs.existsSync @clientPath

  _writeClientLibrary: ->
    return if @fullConfig.virgin or !@clientPath? or fs.existsSync @clientPath

    fs.readFile @mimosaClientLibraryPath, "ascii", (err, data) =>
      return logger.error("Cannot read client library: #{@mimosaClientLibraryPath}") if err?
      fileUtils.writeFile @clientPath, data, (err) =>
        @failed("Cannot write client library: #{err}") if err?

  afterWrite: (fileName) ->
    @optimize()
