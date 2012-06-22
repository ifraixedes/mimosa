watch =     require 'chokidar'
color =     require("ansi-color").set
path =      require 'path'
wrench =    require 'wrench'
fs =        require 'fs'
logger =    require '../util/logger'
optimizer = require '../util/require-optimize'

class Watcher

  compilers:[]

  startWatch: (@srcDir, @compDir, @ignored) ->
    files = wrench.readdirSyncRecursive(@srcDir)
    files = files.filter (file) => fs.statSync(path.join(@srcDir, file)).isFile()
    fileCount = files.length

    addTotal = 0
    watcher = watch.watch(@srcDir, {persistent:true})
    watcher.on "change", (f) => @_findCompiler(f, @_updated)
    watcher.on "unlink", (f) => @_findCompiler(f, @_removed)
    watcher.on "add", (f) =>
      @_findCompiler(f, @_created)
      @_startupFinished() if ++addTotal is fileCount

    logger.info "Watching #{@srcDir}"

  _startupFinished: ->
    compiler.doneStartup() for ext, compiler of @compilers
    optimizer.optimize(@compDir)

  registerCompilers: (compilers) ->
    @compilers.push(compiler) for compiler in compilers

  _findCompiler: (fileName, callback) ->
    return if @ignored.some((str) -> fileName.has(str))
    extension = path.extname(fileName).substring(1)
    return unless extension?.length > 0
    compiler = @compilers.find (comp) ->
      for ext in comp.getExtensions()
        return true if extension is ext
      return false
    if compiler?
      callback(fileName, compiler)
    else
      logger.warn "No compiler has been registered: #{extension}"

  _created: (f, compiler) => @_executeCompilerMethod(f, compiler.created, "created")
  _updated: (f, compiler) => @_executeCompilerMethod(f, compiler.updated, "updated")
  _removed: (f, compiler) => @_executeCompilerMethod(f, compiler.removed, "removed")

  _executeCompilerMethod: (fileName, compilerMethod, name) =>
    if compilerMethod?
      compilerMethod(fileName)
    else
      logger.error "Compiler method #{name} does not exist, doing nothing for #{fileName}"

module.exports = (config) ->

  sourceDir = path.join(config.root, config.watch.sourceDir)
  compiledDir = path.join(config.root, config.watch.compiledDir)

  watcher = new Watcher
  watcher.startWatch(sourceDir, compiledDir, config.watch.ignored)
  watcher