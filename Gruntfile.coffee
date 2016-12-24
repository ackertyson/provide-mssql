module.exports = (grunt) ->
  grunt.initConfig
    pkg: grunt.file.readJSON('package.json')

    clean:
      default: ['dist']

    coffee:
      default:
        expand: true
        cwd: 'src'
        src: '*.coffee'
        dest: 'dist/'
        ext: '.js'
        sourceMap: true

    mochaTest:
      test:
        src: [ 'test/**/*.coffee' ]

    uglify:
      default:
        files:
          'dist/index.min.js': ['dist/index.js']

  grunt.loadNpmTasks('grunt-contrib-clean')
  grunt.loadNpmTasks('grunt-contrib-coffee')
  grunt.loadNpmTasks('grunt-contrib-uglify')
  grunt.loadNpmTasks('grunt-mocha-test')

  grunt.registerTask('test', ['mochaTest'])
  grunt.registerTask('default', ['clean', 'coffee', 'uglify'])
