# The Open Graph preview banners: what a link to this app looks like pasted into a chat.
# Og::SitePayload and its three siblings decide what one banner *says*, Og::Renderer draws it,
# Og::Cache addresses the file, and Ui::OgTags prints the address.
#
# This file exists to make `Og` an **explicit** Zeitwerk namespace, and that is not cosmetic.
# Without it `Og` is implicit — conjured from the directory name — and Zeitwerk autoloads
# `Og::Payload` but not the constants that were declared beside it, so `Og::LAYOUT_VERSION` from a
# caller that had not already touched `Og::Payload` raised `NameError`. It raised in development
# and in a local test run only: `config.eager_load = ENV["CI"].present?` loads everything in CI, so
# the one environment that would have caught it is the one that hides it. Declaring the constants
# here means reading either of them loads this file, which is all Zeitwerk needs.
module Og
  # The banner's drawing, versioned. It is the first term of every digest, so bumping it moves
  # every subject's cache path and every `?v=` at once — without it, editing the design leaves
  # every already-generated file in place and the change appears to do nothing.
  LAYOUT_VERSION = 1

  # How many cards the layout draws. Fewer is normal — a deck with one notable Pokémon, a card
  # page — and zero falls back to the branded banner with no artwork at all.
  MAX_ARTS = 2
end
