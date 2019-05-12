describe TagsController do
  before :each do
    # Authenticate user is not timed out, and has administrator rights.
    allow(controller).to receive(:session_expired?).and_return(false)
    allow(controller).to receive(:logged_in?).and_return(true)
    allow(controller).to receive(:current_user).and_return(build(:admin))
  end

  let(:assignment) { FactoryBot.create(:assignment) }

  context 'File Uploads' do
    before :each do
      # We need to mock the rack file to return its content when
      # the '.read' method is called to simulate the behaviour of
      # the http uploaded file
      @file_good_csv = fixture_file_upload(
        'files/tags/form_good.csv', 'text/csv'
      )
      allow(@file_good).to receive(:read).and_return(
        File.read(fixture_file_upload(
                    'files/tags/form_good.csv',
                    'text/csv'
                  ))
      )

      @file_good_yml = fixture_file_upload(
        'files/tags/form_good.yml', 'text/yaml'
      )
      allow(@file_good_yml).to receive(:read).and_return(
        File.read(fixture_file_upload('files/tags/form_good.yml', 'text/yaml'))
      )

      @file_invalid_column = fixture_file_upload(
        'files/tags/form_invalid_column.csv', 'text/csv'
      )
      allow(@file_invalid_column).to receive(:read).and_return(
        File.read(fixture_file_upload(
                    'files/tags/form_invalid_column.csv',
                    'text/csv'
                  ))
      )

      @file_bad_csv = fixture_file_upload(
        'files/bad_csv.csv', 'text/xls'
      )
      allow(@file_bad_csv).to receive(:read).and_return(
        File.read(fixture_file_upload('files/bad_csv.csv', 'text/csv'))
      )

      @file_wrong_format = fixture_file_upload(
        'files/wrong_csv_format.xls', 'text/xls'
      )
      allow(@file_wrong_format).to receive(:read).and_return(
        File.read(fixture_file_upload(
                    'files/wrong_csv_format.xls', 'text/csv'
                  ))
      )

      # set the :back redirect
      @redirect = 'index'
      request.env['HTTP_REFERER'] = @redirect
    end

    it 'accepts a valid CSV file' do
      post :csv_upload, params: { csv_tags: @file_good_csv, assignment_id: assignment.id }

      expect(response.status).to eq(302)
      expect(flash[:error]).to be_nil
      expect(flash[:success].map { |f| extract_text f }).to eq([I18n.t('upload_success',
                                                                       count: 2)].map { |f| extract_text f })
      expect(response).to redirect_to @redirect

      expect(Tag.where(name: 'tag').take['description']).to eq('desc')
      expect(Tag.where(name: 'tag1').take['description']).to eq('desc1')
    end

    it 'accepts a valid YAML file' do
      pending('downloading YML files does not work due to expected, got id which is an instance of String error')
      post :yml_upload, params: { yml_tags: @file_good_yml, assignment_id: assignment.id }

      expect(response.status).to eq(302)
      expect(flash[:error]).to be_nil
      expect(response).to redirect_to @redirect

      expect(Tag.where(name: 'tag').take['description']).to eq('desc')
      expect(Tag.where(name: 'tag1').take['description']).to eq('desc1')
    end

    it 'does not accept files with invalid columns' do
      post :csv_upload, params: { assignment_id: assignment.id, csv_tags: @file_invalid_column }

      expect(response.status).to eq(302)
      expect(flash[:error]).to_not be_empty
      expect(response).to redirect_to @redirect
    end

    it 'does not accept fileless submission' do
      post :csv_upload, params: { assignment_id: assignment.id }

      expect(response.status).to eq(302)
      expect(response).to redirect_to @redirect
    end

    it 'does not accept a non-csv file with .csv extension' do
      post :csv_upload, params: { assignment_id: assignment.id, csv_tags: @file_bad_csv }

      expect(response.status).to eq(302)
      expect(flash[:error]).to_not be_empty
      expect(response).to redirect_to @redirect
    end

    it 'does not accept a .xls file' do
      post :csv_upload, params: { assignment_id: assignment.id, csv_tags: @file_wrong_format }

      expect(response.status).to eq(302)
      expect(flash[:error]).to_not be_empty
      expect(extract_text(flash[:error][0]))
        .to eq(extract_text(I18n.t('upload_errors.unparseable_csv')))
      expect(response).to redirect_to @redirect
    end
  end

  context 'File Downloads' do
    context 'csv' do
      let(:csv_options) do
        {
          type: 'text/csv',
          disposition: 'attachment',
          filename: 'tag_list.csv'
        }
      end

      before :each do
        @user = create(:student)
        @tag1 = Tag.find_or_create_by(name: 'tag1')
        @tag1.name = 'tag1'
        @tag1.description = 'tag1_description'
        @tag1.user = @user
        @tag1.save

        @tag2 = Tag.find_or_create_by(name: 'tag2')
        @tag2.name = 'tag2'
        @tag2.description = 'tag2_description'
        @tag2.user = @user
        @tag2.save
      end

      it 'responds with appropriate status' do
        get :download_tag_list, params: { assignment_id: assignment.id }, format: 'csv'
        expect(response.status).to eq(200)
      end

      # parse header object to check for the right disposition
      it 'sets disposition as attachment' do
        get :download_tag_list, params: { assignment_id: assignment.id }, format: 'csv'
        d = response.header['Content-Disposition'].split.first
        expect(d).to eq 'attachment;'
      end

      it 'expects a call to send_data' do
        csv_data =
          "#{@tag1.name},#{@tag1.description},#{@user.first_name} #{@user.last_name}\n" \
            "#{@tag2.name},#{@tag2.description},#{@user.first_name} #{@user.last_name}\n"
        expect(@controller).to receive(:send_data).with(csv_data, csv_options) {
          # to prevent a 'missing template' error
          @controller.head :ok
        }
        get :download_tag_list, params: { assignment_id: assignment.id }, format: 'csv'
      end

      # parse header object to check for the right content type
      it 'returns text/csv type' do
        get :download_tag_list, params: { assignment_id: assignment.id }, format: 'csv'
        expect(response.content_type).to eq 'text/csv'
      end
    end

    context 'yml' do
      let(:yml_options) do
        {
          type: 'text/yml',
          disposition: 'attachment',
          filename: 'tag_list.yml'
        }
      end

      before :each do
        @user = create(:student)
        @tag1 = Tag.find_or_create_by(name: 'tag1')
        @tag1.name = 'tag1'
        @tag1.description = 'tag1_description'
        @tag1.user = @user
        @tag1.save

        @tag2 = Tag.find_or_create_by(name: 'tag2')
        @tag2.name = 'tag2'
        @tag2.description = 'tag2_description'
        @tag2.user = @user
        @tag2.save
      end

      it 'responds with appropriate status' do
        pending("currently downloading YML files does not work due to a couldn't find User without an ID error")
        get :download_tag_list, params: { assignment_id: assignment.id }, format: 'yml'
        expect(response.status).to eq(200)
      end

      # parse header object to check for the right disposition
      it 'sets disposition as attachment' do
        pending("currently downloading YML files does not work due to a couldn't find User without an ID error")
        get :download_tag_list, params: { assignment_id: assignment.id }, format: 'yml'
        d = response.header['Content-Disposition'].split.first
        expect(d).to eq 'attachment;'
      end

      it 'expects a call to send_data' do
        pending("currently downloading YML files does not work due to a couldn't find User without an ID error")
        yml_data =
          "#{@tag1.name}:\n #{@tag1.description}:\n #{@user.first_name} #{@user.last_name}\n" \
            "#{@tag2.name}:\n #{@tag2.description}:\n #{@user.first_name} #{@user.last_name}\n"
        expect(@controller).to receive(:send_data).with(yml_data, yml_options) {
          # to prevent a 'missing template' error
          @controller.head :ok
        }
        get :download_tag_list, params: { assignment_id: assignment.id }, format: 'yml'
      end

      # parse header object to check for the right content type
      it 'returns text/yml type' do
        pending("currently downloading YML files does not work due to a couldn't find User without an ID error")
        get :download_tag_list, params: { assignment_id: assignment.id }, format: 'yml'
        expect(response.content_type).to eq 'text/yml'
      end
    end
  end
end
