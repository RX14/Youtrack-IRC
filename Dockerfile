FROM ruby:2.2.2

RUN \
  apt-get update && \
  apt-get install --no-install-recommends -y git

WORKDIR /youtrack-irc/
ADD . /youtrack-irc/

RUN bundle install

CMD ["/usr/local/bundle/bin/bundler", "exec", "ruby", "/youtrack-irc/youtrack-irc.rb"]