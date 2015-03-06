
module Jenkins::Utils

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

