
module Jenkins

#  # Esta de momento sobra, hara falta para lo del autopublicar el resultado de los tests
#  class FilePath
#    def write(string, encoding='UTF-8')
#      @native.write(string, encoding)
#    end
#  end

  module Utils
    java_import Java.hudson.plugins.git.extensions.impl.RelativeTargetDirectory

    def topdir( build )
      target = build.native.project.scm.extensions.get RelativeTargetDirectory.java_class
      if target && local_branch = target.relative_target_dir
        build.workspace + local_branch
      else
        build.workspace
      end
    end
  end

end

