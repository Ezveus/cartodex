# Harvests the consent form actually rendered by GET /oauth/authorize into the
# params a browser would build from it: every hidden field, plus one value per
# non-disabled checked checkbox.
#
# This is what stands between the two most dangerous silent failures in that
# screen — a dropped code_challenge hidden field, or a dropped hidden mirror of
# the disabled mcp:read checkbox — and a test that would actually notice.
# Hand-building the POST params can't see either regression, because it never
# reads the form at all.
#
# Shared between OauthConsentTest (which exercises the screen) and
# OauthEndToEndTest (which drives the whole connector flow through it), so the
# end-to-end test cannot quietly diverge from the form the user really submits.
module OauthConsentForm
  # exclude_checkbox_values simulates the user unchecking a box: a disabled
  # checkbox is never in this set to begin with (real browsers don't submit
  # disabled inputs either), so excluding mcp:read here would prove nothing —
  # only a genuinely optional, checked box belongs in the argument.
  #
  # Scoped to #consent-authorize-form: the screen renders a second form (Deny,
  # DELETE) with its own hidden-field mirror right below it, method-override
  # field included — an unscoped query would harvest both indiscriminately and
  # hand the POST a stray _method=delete along with duplicate fields.
  def harvest_form_params(exclude_checkbox_values: [])
    params = Hash.new { |hash, key| hash[key] = [] }

    css_select("#consent-authorize-form input[type=hidden]").each { |field| collect_field(params, field) }
    css_select("#consent-authorize-form input[type=checkbox]:not([disabled])").each do |checkbox|
      next if exclude_checkbox_values.include?(checkbox["value"])

      collect_field(params, checkbox)
    end

    params
  end

  def collect_field(params, field)
    name = field["name"]
    if name.end_with?("[]")
      params[name.delete_suffix("[]")] << field["value"]
    else
      params[name] = field["value"]
    end
  end
end
