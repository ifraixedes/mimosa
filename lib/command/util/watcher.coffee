path =      require 'path'

watch =     require 'chokidar'
_ =         require 'lodash'

logger =    require '../../util/logger'
optimizer = require '../../util/require/optimize'

class Watcher

  compilersDone:0
  adds:[]

  constructor: (@config, @compilers, @persist, @initCallback) ->
    @throttle = @config.watch.throttle
    compiler.setStartupDoneCallback(@compilerDone) for compiler in @compilers
    @startWatcher()

    logger.info "Watching #{@config.watch.sourceDir}" if @persist

    if @throttle > 0
      @intervalId = setInterval(@pullFiles, 100)
      @pullFiles()

  startWatcher: (persist) ->
    watcher = watch.watch(@config.watch.sourceDir, {persistent:@persist})
    watcher.on "change", (f) => @_findCompiler(f)?.updated(f)
    watcher.on "unlink", (f) => @_findCompiler(f)?.removed(f)
    watcher.on "add", (f) =>
      if @throttle > 0 then @adds.push(f) else @_findCompiler(f)?.created(f)

  pullFiles: =>
    return if @adds.length is 0
    filesToAdd = if @adds.length <= @throttle
      clearInterval(@intervalId) unless @persist
      @adds.splice(0, @adds.length)
    else
      @adds.splice(0, @throttle)
    @_findCompiler(f)?.created(f) for f in filesToAdd

  compilerDone: =>
    if ++@compilersDone is @compilers.length
      compiler.initializationComplete() for compiler in @compilers
      optimizer.optimize(@config)
      @initCallback(@config) if @initCallback?

  _findCompiler: (fileName) ->
    return if @config.watch.ignored.some((str) -> fileName.indexOf(str) >= 0 )

    extension = path.extname(fileName).substring(1)
    return unless extension?.length > 0

    compiler = _.find @compilers, (comp) ->
      for ext in comp.getExtensions()
        return true if extension is ext
      return false

    return compiler if compiler
    logger.warn "No compiler has been registered: #{extension}, #{fileName}"
    null

module.exports = Watcher
