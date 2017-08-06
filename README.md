
# build

jruby is obviously a requirement

    PATH=$PATH:/opt/jruby-1.7.18/bin:$HOME/.gem/jruby/1.9/bin
    JRUBY_HOME=/opt/jruby-1.7.18
    export PATH JRUBY_HOME
    
    jruby -S bundle install --path bundle
    jruby -S bundle exec jpi build

