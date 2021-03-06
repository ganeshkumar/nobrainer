require 'spec_helper'

describe 'NoBrainer callbacks' do
  before { load_simple_document }

  context 'when using a simple validation' do
    before { SimpleDocument.validates :field1, :presence => true }

    it 'responds to valid?' do
      doc = SimpleDocument.new
      doc.valid?.should == false
      doc.field1 = 'hey'
      doc.valid?.should == true
    end

    it 'responds to invalid?' do
      doc = SimpleDocument.new
      doc.invalid?.should == true
      doc.field1 = 'hey'
      doc.invalid?.should == false
    end

    it 'adds errors' do
      SimpleDocument.create.errors.should be_present
    end

    context 'when not using the bang version' do
      let(:doc) { SimpleDocument.create(:field1 => 'ohai') }

      it 'prevents create if invalid' do
        SimpleDocument.count.should == 0
      end

      context 'when passing :validate => false' do
        it 'returns true for save' do
          doc.field1 = nil
          doc.save(:validate => false).should == true
        end
      end

      context 'when passing nothing' do
        it 'returns false for save' do
          doc.field1 = nil
          doc.save.should == false
        end
      end

      it 'returns false for update_attributes' do
        doc.update_attributes(:field1 => nil).should == false
      end
    end

    context 'when using the bang version' do
      let(:doc) { SimpleDocument.create(:field1 => 'ohai') }

      it 'throws an exception for create!' do
        expect { SimpleDocument.create! }
          .to raise_error(NoBrainer::Error::DocumentInvalid, /Field1 can't be blank/)
      end

      context 'when passing :validate => false' do
        it 'returns true for save!' do
          doc.field1 = nil
          doc.save!(:validate => false).should == true
        end
      end

      context 'when passing nothing' do
        it 'throws an exception for save!' do
          doc.field1 = nil
          expect { doc.save! }.to raise_error(NoBrainer::Error::DocumentInvalid)
        end
      end

      it 'throws an exception for update_attributes!' do
        expect { doc.update_attributes!(:field1 => nil) }.to raise_error(NoBrainer::Error::DocumentInvalid)
      end
    end
  end

  context 'when using an ActiveModel validation' do
    context 'when using validates_XXX_of' do
      before { SimpleDocument.validates_numericality_of :field1 }
      it 'validates' do
        SimpleDocument.new(:field1 => 'hello').valid?.should == false
        SimpleDocument.new(:field1 => 3).valid?.should == true
      end
    end

    context 'when using validates' do
      before { SimpleDocument.validates :field1, :numericality => true }
      it 'validates' do
        SimpleDocument.new(:field1 => 'hello').valid?.should == false
        SimpleDocument.new(:field1 => 3).valid?.should == true
      end
    end

    context 'when using validate' do
      before do
        SimpleDocument.class_eval do
          validate :some_validator
          def some_validator
            errors.add(:base, "oh no")
          end
        end
      end

      it 'validates' do
        SimpleDocument.new.valid?.should == false
      end
    end
  end

  context 'when using validates on the field' do
    before { SimpleDocument.field :field1, :validates => { :numericality => true } }

    it 'validates' do
      SimpleDocument.new(:field1 => 'hello').valid?.should == false
      SimpleDocument.new(:field1 => 3).valid?.should == true
    end
  end

  context 'when using validates on a belongs_to' do
    before { load_blog_models }
    before { Comment.belongs_to :post, :validates => { :presence => true } }

    it 'validates' do
      post = Post.create
      Comment.new.valid?.should == false
      Comment.new(:post => post).valid?.should == true
    end
  end

  context 'when using unique on the field' do
    before { SimpleDocument.field :field1, :unique => true }

    it 'validates' do
      SimpleDocument.new(:field1 => 123).save.should == true
      SimpleDocument.new(:field1 => 123).save.should == false
    end
  end

  context 'when using required on the field' do
    before { SimpleDocument.field :field1, :required => true }

    it 'validates' do
      SimpleDocument.new(:field1 => nil).valid?.should == false
      SimpleDocument.new(:field1 => 'ohai').valid?.should == true
    end
  end

  context 'when using required on a belongs_to' do
    before { load_blog_models }
    before { Comment.belongs_to :post, :required => true }

    it 'validates' do
      post = Post.create
      c = Comment.create({}, :validate => false)

      c.post = Post.new
      expect { c.valid? }.to raise_error(NoBrainer::Error::AssociationNotPersisted)

      c.post = post
      c.post_id.should == post.id
      c.valid?.should == true

      c.post = nil
      c.post_id.should == nil
      c.valid?.should == false

      c.post_id = '123'
      c.valid?.should == false

      c.post_id = post.id
      c.valid?.should == true
      Post.delete_all
      c.valid?.should == true

      c.post_id = post.id
      c.valid?.should == false
    end
  end
end
