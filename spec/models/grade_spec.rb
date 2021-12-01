describe Grade do
  subject { create :grade }
  it { is_expected.to validate_numericality_of(:grade) }

  it { is_expected.to allow_value(0.0).for(:grade) }
  it { is_expected.to allow_value(1.5).for(:grade) }
  it { is_expected.to allow_value(100.0).for(:grade) }
  it { is_expected.to_not allow_value(-0.5).for(:grade) }
  it { is_expected.to_not allow_value(-1.0).for(:grade) }
  it { is_expected.to_not allow_value(-100.0).for(:grade) }

  it { is_expected.to belong_to(:grade_entry_item) }
  it { is_expected.to belong_to(:grade_entry_student) }
  it { is_expected.to have_one(:course) }
  include_examples 'course associations'
end
