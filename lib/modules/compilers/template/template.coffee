path = require 'path'
fs =   require 'fs'

wrench = require 'wrench'
_ =      require 'lodash'

requireRegister =  require '../../require/register'
fileUtils =        require '../../../util/file'
logger =           require '../../../util/logger'

module.exports = class AbstractTemplateCompiler

  constructor: (@config) ->
    jsDir = path.join @config.watch.compiledDir, @config.watch.javascriptDir
    @templateFileName = if @config.template.outputFileName[@constructor.base]
      path.join(jsDir, @config.template.outputFileName[@constructor.base] + ".js")
    else
      path.join(jsDir, @config.template.outputFileName + ".js")

    if @clientLibrary?
      @mimosaClientLibraryPath = path.join __dirname, "client", "#{@clientLibrary}.js"
      @clientPath = path.join jsDir, 'vendor', "#{@clientLibrary}.js"

  lifecycleRegistration: (config, register) ->
    register ['add','update','postStartup','delete'], 'init',       [@extensions...], @_gatherFiles
    register ['add','update','postStartup','delete'], 'beforeRead', [@extensions...], @_templateNeedsCompiling
    register ['add','update','postStartup','delete'], 'read',       [@extensions...], @_readTemplateFiles
    register ['add','update','postStartup','delete'], 'compile',    [@extensions...], @_compile

    unless config.virgin
      register ['delete'],                       'beforeRead',  [@extensions...], @_testForRemoveClientLibrary
      register ['add', 'update', 'postStartup'], 'beforeWrite', [@extensions...], @_writeClientLibrary

  _gatherFiles: (config, options, next) ->
    logger.debug "Gathering files for templates"
    allFiles = wrench.readdirSyncRecursive(config.watch.srcDir)
      .map (file) => path.join(config.watch.srcDir, file)

    fileNames = []
    for file in allFiles
      extension = path.extname(file).substring(1)
      fileNames.push(file) if @extensions.indexOf(extension) >= 0

    @_testForSameTemplateName(fileNames) unless fileNames.length <= 1

    options.templatefileNames = fileNames

    next()

  _readTemplateFiles: (config, options, next) ->
    options.templateContentByName = {}
    numFiles = options.templatefileNames.length
    done = ->
      next() if ++numFiles is options.templatefileNames.length

    for fileName in options.templatefileNames
      fs.readFile fileName, "ascii", (err, content) ->
        templateName = path.basename fileName, path.extname(fileName)
        options.templateContentByName[templateName] = [fileName, content]
        done()

  _testForRemoveClientLibrary: (config, options, next) ->
    if options.templatefileNames?.length is 0
      logger.debug "No template files left, removing [[ #{@templateFileName} ]]"
      @removeClientLibrary(next)
    else
      next()

  removeClientLibrary: (callback) ->
    if @clientPath?
      fs.exists @clientPath, (exists) ->
        if exists
          logger.debug "Removing client library [[ #{@clientPath} ]]"
          fs.unlinkSync @clientPath, (err) -> callback()
        else
          callback()
    else
      callback()

  _testForSameTemplateName: (fileNames) ->
    templateHash = {}
    for fileName in fileNames
      templateName = path.basename(fileName, path.extname(fileName))
      if templateHash[templateName]?
        logger.error "Files [[ #{templateHash[templateName]} ]] and [[ #{fileName} ]] result in templates of the same name " +
                     "being created.  You will want to change the name for one of them or they will collide."
      else
        templateHash[templateName] = fileName

  _templateNeedsCompiling: (config, options, next) ->
    fileNames = options.templatefileNames
    numFiles = fileNames.length

    i = 0
    processFile = =>
      if i < numFiles
        fileUtils.isFirstFileNewer fileNames[i], @templateFileName, cb
      else
        next(false)

    cb = (isNewer) =>
      if isNewer then next() else processFile()

    processFile()

  _writeClientLibrary: (config, options, next) ->
    if !@clientPath? or fs.existsSync @clientPath
      logger.debug "Not going to write template client library"
      return next()

    logger.debug "Writing template client library [[ #{@mimosaClientLibraryPath} ]]"
    fs.readFile @mimosaClientLibraryPath, "ascii", (err, data) =>
      return next({text:"Cannot read client library: #{@mimosaClientLibraryPath}"}) if err?

      fileUtils.writeFile @clientPath, data, (err) =>
        return next({text:"Cannot write client library: #{err}"}) if err?
        next()

  libraryPath: ->
    libPath = "vendor/#{@clientLibrary}"
    requireRegister.aliasForPath(libPath) ? libPath

  templatePreamble: (fileName, templateName) ->
    """
    \n//
    // Source file: [#{fileName}]
    // Template name: [#{templateName}]
    //\n
    """

  addTemplateToOutput: (fileName, templateName, source) =>
    """
    #{@templatePreamble(fileName, templateName)}
    templates['#{templateName}'] = #{source};\n
    """