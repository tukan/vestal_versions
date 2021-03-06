require File.join(File.dirname(__FILE__), 'test_helper')

class ReversionTest < Test::Unit::TestCase
  context 'A model reversion' do
    setup do
      @user, @attributes, @times = User.new, {}, {}
      names = ['Steve Richert', 'Stephen Richert', 'Stephen Jobs', 'Steve Jobs']
      time = names.size.hours.ago
      names.each do |name|
        @user.update_attribute(:name, name)
        @attributes[@user.version] = @user.attributes
        time += 1.hour
        if last_version = @user.versions.last
          last_version.update_attribute(:created_at, time)
        end
        @times[@user.version] = time
      end
      @user.reload.versions.reload
      @first_version, @last_version = @attributes.keys.min, @attributes.keys.max
    end

    should 'return the new version number' do
      new_version = @user.revert_to(@first_version)
      assert_equal @first_version, new_version
    end

    should 'change the version number when saved' do
      current_version = @user.version
      @user.revert_to!(@first_version)
      assert_not_equal current_version, @user.version
    end

    should 'do nothing for a invalid argument' do
      current_version = @user.version
      [nil, :bogus, 'bogus', (1..2)].each do |invalid|
        @user.revert_to(invalid)
        assert_equal current_version, @user.version
      end
    end

    should 'be able to target a version number' do
      @user.revert_to(1)
      assert 1, @user.version
    end

    should 'be able to target a date and time' do
      @times.each do |version, time|
        @user.revert_to(time + 1.second)
        assert_equal version, @user.version
      end
    end

    should 'be able to target a version object' do
      @user.versions.each do |version|
        @user.revert_to(version)
        assert_equal version.number, @user.version
      end
    end

    should "correctly roll back the model's attributes" do
      timestamps = %w(created_at created_on updated_at updated_on)
      @attributes.each do |version, attributes|
        @user.revert_to!(version)
        assert_equal attributes.except(*timestamps), @user.attributes.except(*timestamps)
      end
    end
  end
end
