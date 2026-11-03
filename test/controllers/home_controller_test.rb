require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "renders chat, cards and map" do
    get root_path
    assert_response :success
    assert_select "aside", text: /Most programs nearby end at 5:00 pm/
    assert_select "article[data-school-id]", 3
    assert_select "section[aria-label='Map of results'] svg"
    assert_select "article", text: /No rating yet/
  end
end
