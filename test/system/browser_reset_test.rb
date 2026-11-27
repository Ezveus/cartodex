require "application_system_test_case"

# Between two tests the browser must forget the previous one's cookies and local storage. Capybara's
# own reset does that with a wildcard origin Chrome 158 refuses, so ApplicationSystemTestCase clears
# them another way — this is what holds that the other way still clears both.
class BrowserResetTest < ApplicationSystemTestCase
  test "a session reset clears the page's cookies and local storage" do
    visit root_path
    execute_script(<<~JS)
      document.cookie = "reset_probe=1; path=/";
      localStorage.setItem("reset_probe", "1");
    JS
    assert_equal "1", evaluate_script(%(localStorage.getItem("reset_probe")))

    Capybara.current_session.reset!
    visit root_path

    assert_not_includes evaluate_script("document.cookie"), "reset_probe"
    assert_nil evaluate_script(%(localStorage.getItem("reset_probe")))
  end
end
