
RSpec.describe "Language", "basic functions" do
  it "has working inc" do
    expect(%Q{(print (inc 4))}).to have_output("5")
  end

  it "has working dec" do
    expect(%Q{(print (dec 277))}).to have_output("276")
  end

  it "has working nil?" do
    expect(%Q{(print (nil? nil))}).to have_output("true")
    expect(%Q{(print (nil? 42))}).to  have_output("false")
  end

  it "has working not" do
    expect(%Q{(print (not true))}).to    have_output("false")
    expect(%Q{(print (not 42))}).to      have_output("false")
    expect(%Q{(print (not "hello"))}).to have_output("false")
    expect(%Q{(print (not false))}).to   have_output("true")
    expect(%Q{(print (not nil))}).to     have_output("true")
  end

  it "has working even?" do
    expect(%Q{(print (even? 25073942))}).to have_output("true")
    expect(%Q{(print (even? 3))}).to have_output("false")
  end

  it "has working odd?" do
    expect(%Q{(print (odd? 25073942))}).to have_output("false")
    expect(%Q{(print (odd? 3))}).to have_output("true")
  end
end

