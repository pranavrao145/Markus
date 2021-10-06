describe CoursePolicy do
  let(:context) { { user: user } }
  let(:user) { create :student }
  describe_rule :manage? do
    failed
  end
  describe_rule :show? do
    succeed
  end
  describe_rule :index? do
    succeed
  end
end
