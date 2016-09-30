// Test class for Bouquet Application
@isTest
private class BouquetAppTest {
	// Load Initial data for all test methods
	@testSetup
	static void setUpTestData() {
		List<Lead> customers = Test.loadData(Lead.SObjectType, 'TestData_Customers');
		List<Product2> flowers = Test.loadData(Product2.SObjectType, 'TestData_Flowers');
	}

	// Help method to create test users
	private static User createUser(Profile p, Integer index) {
		String idxVal = String.valueOf(index);

		User u = new User();
		u.ProfileId = p.id;

		u.alias = 'alias' + idxVal;
		u.email = 'test' + idxVal + '@testclass-abcdefg.com';
		u.emailencodingkey = 'UTF-8';
		u.firstname = 'firstname' + idxVal;
		u.lastname = 'lastname' + idxVal;
		u.languagelocalekey = 'en_US';
		u.localesidkey = 'en_US';
		u.timezonesidkey = 'America/Los_Angeles';

		u.username = u.email;

		return u;
	}

	// Help method to create Inventory Manager User
	static User getInventoryManagerUser() {
		Profile pManager = [SELECT Name FROM Profile WHERE Name='Inventory Manager'];
		User u = createUser(pManager, 0);
		
		//User u = [SELECT Name FROM User WHERE FirstName='Irene' AND LastName='Inventory'];
		System.debug('Running User: ' + JSON.serialize(u));

		return u;
	}

	// Help method to create Florist User A
	static User getFloristUserA() {
		Profile pFlorist = [SELECT Name FROM Profile WHERE Name='Florist'];
		User u = createUser(pFlorist, 1);
		//User u = [SELECT Name FROM User WHERE FirstName='Fred' AND LastName='Florist'];

		System.debug('Running User: ' + JSON.serialize(u));
		return u;
	}

	// Help method to create Florist User A
	static User getFloristUserB() {
		Profile pFlorist = [SELECT Name FROM Profile WHERE Name='Florist'];
		User u = createUser(pFlorist, 2);
		//User u = [SELECT Name FROM User WHERE FirstName='Otto' AND LastName='Otherguy'];

		System.debug('Running User: ' + JSON.serialize(u));
		return u;
	}

	// Test the data visibility
	@isTest
	static void testSecurityDataAccess() {
		Lead customer = [SELECT Street, FirstName, LastName FROM Lead LIMIT 1];
		System.runAs(getFloristUserA()) {
			Bouquet__c bouquet = new Bouquet__c(
				Customer__c = customer.Id
				);
			insert bouquet;

			System.assertEquals(1, [SELECT Id FROM Bouquet__c].size());
		}		

		System.runAs(getFloristUserB()) {
			// Florist User B cannot see the bouquet created by Florist User A
			System.assertEquals(0, [SELECT Id FROM Bouquet__c].size());

			Bouquet__c bouquet = new Bouquet__c(
				Customer__c = customer.Id
				);
			insert bouquet;
		}

		System.runAs(getInventoryManagerUser()) {
			// Inventory Manager can see the record created by Florist user(s)
			System.assertEquals(2, [SELECT Id FROM Bouquet__c].size());
		}
	}

	// Test the VF (BouquetBuilder) access right per profiles
	@isTest
	static void testSecurityVfAccess() {
		ApexPage bbPage = [SELECT Id FROM ApexPage WHERE Name='BouquetBuilder'];
		Profile pFlorist = [SELECT Name FROM Profile WHERE Name='Florist'];
		Profile pManager = [SELECT Name FROM Profile WHERE Name='Inventory Manager'];

		System.assertEquals(1, [SELECT Id FROM SetupEntityAccess WHERE Parent.Profile.Id = :pFlorist.Id AND SetupEntityId = :bbPage.Id].size());
		System.assertEquals(0, [SELECT Id FROM SetupEntityAccess WHERE Parent.Profile.Id = :pManager.Id AND SetupEntityId = :bbPage.Id].size());
	}

	// Test the Most_Used_Color__c and Inventory_Used__c fields
	@isTest
	static void testAutoLogic() {
		System.runAs(getFloristUserA()) {
			// Get the customer/flower records for the later test
			Set<String> flowerNames = new Set<String> {
				'Abracadabra',	// Green
				'Camellia Foliage',	// Green
				'Moth'	// Pink
			};

			Lead customer = [SELECT Street, FirstName, LastName FROM Lead LIMIT 1];
			Product2 fAbracadabra, fMoth, fCamellia;
			for (Product2 f : [SELECT Name, Family, Color__c, Initial_Inventory__c, IsActive FROM Product2 WHERE Name IN :flowerNames]) {
				if (f.Name == 'Abracadabra') fAbracadabra = f;
				else if (f.Name == 'Camellia Foliage') fCamellia= f;
				else if (f.Name == 'Moth') fMoth= f;
			}

			// Add a bouquet 
			Bouquet__c bq = new Bouquet__c(
				Customer__c = customer.Id,
				Deliver_To__c = customer.Street,
				Delivery_Date__c = Date.today(),
				Message__c = 'Test Message'
				);
			insert bq;
			bq = [SELECT Customer__c, Delivery_Date__c, Deliver_To__c, Message__c FROM Bouquet__c WHERE Id = :bq.Id];

			Bloom__c bmAbracadabra = new Bloom__c(
				Bouquet__c = bq.Id,
				Flower__c = fAbracadabra.Id,
				Quantity__c = 2
				);
			Bloom__c bmMoth = new Bloom__c(
				Bouquet__c = bq.Id,
				Flower__c = fMoth.Id,
				Quantity__c = 8 // 8 > 2 + 4 -> Most_Used_Color is Pink
				);
			Bloom__c bmCamellia = new Bloom__c(
				Bouquet__c = bq.Id,
				Flower__c = fCamellia.Id,
				Quantity__c = 4
				);

			insert new List<Bloom__c> { bmAbracadabra, bmCamellia, bmMoth };
			System.assertEquals(fMoth.Color__c, [SELECT Most_Used_Color__c FROM Lead WHERE Id=:customer.Id].Most_Used_Color__c);
			for (Product2 f : [SELECT Name, Family, Color__c, Initial_Inventory__c, Inventory_Used__c, IsActive FROM Product2 WHERE Name IN :flowerNames]) {
				if (f.Name == 'Abracadabra') {
					System.assertEquals(f.Inventory_Used__c, bmAbracadabra.Quantity__c);
				} else if (f.Name == 'Camellia Foliage') { 
					System.assertEquals(f.Inventory_Used__c, bmCamellia.Quantity__c);
				} else if (f.Name == 'Moth') {
					System.assertEquals(f.Inventory_Used__c, bmMoth.Quantity__c);
				}
			}

			// Test the most used color if the total quantity is tire
			// bmAbracadabra.Quantity__c = 4;
			bmCamellia.Quantity__c = 10;
			bmMoth.Quantity__c = 10;
			update new List<Bloom__c> { bmCamellia, bmMoth };
			delete bmAbracadabra;

			System.assertEquals(fCamellia.Color__c, [SELECT Most_Used_Color__c FROM Lead WHERE Id=:customer.Id].Most_Used_Color__c); // Changed to green of fCamellia's color
			// Verify Inventory_Used__c on updates and deletes
			for (Product2 f : [SELECT Name, Family, Color__c, Initial_Inventory__c, Inventory_Used__c, IsActive FROM Product2 WHERE Name IN :flowerNames]) {
				if (f.Name == 'Abracadabra') {
					System.assertEquals(f.Inventory_Used__c, 0);
				} else if (f.Name == 'Camellia Foliage') { 
					System.assertEquals(f.Inventory_Used__c, bmCamellia.Quantity__c);
				} else if (f.Name == 'Moth') {
					System.assertEquals(f.Inventory_Used__c, bmMoth.Quantity__c);
				}
			}

		}
	}


	// Test the User Interactive logic, such as pagination, filter, summary etc
	@isTest
	static void testPageUXLogic() {
		PageReference bbRef = Page.BouquetBuilder;
		Test.setCurrentPage(bbRef);

		System.runAs(getFloristUserA()) {
			Lead customer = [SELECT Street, FirstName, LastName FROM Lead LIMIT 1];

			ApexPages.StandardController stdCtrl = new ApexPages.StandardController(new Bouquet__c());
			BouquetBuilderController bbCtrl = new BouquetBuilderController(stdCtrl);

			// Create a new bouquet 
			Bouquet__c bouquet = (Bouquet__c)stdCtrl.getRecord();
			bouquet.Customer__c = customer.Id;
			bouquet.Deliver_To__c = customer.Street;
			bouquet.Message__c = 'Test Message';
			bouquet.Delivery_Date__c = Date.today();

			// Set bouquet flowers
			List<BouquetBuilderController.BouquetFlower> bouquetFlowers = bbCtrl.getBouquetFlowers();
			// Set the value to check later
			bouquetFlowers[0].bloom.Quantity__c = 8;
			Product2 flower1 = bouquetFlowers[0].flower;

			// Test the navigation
			// Move to next page to make sure the selected flower and quantity are remembered
			bbCtrl.next();

			// Verify the page number/page count
			System.assertEquals(2, bbCtrl.getPageNumber());
			System.assertEquals(Math.ceil([SELECT Id FROM Product2].size() / 5.0), bbCtrl.getPageCount());

			// Verify navigation button status
			System.assertEquals(true, bbCtrl.hasPrevious);
			if (bbCtrl.getPageCount() > 2) // 2 is current page
				System.assertEquals(true, bbCtrl.hasNext);

			// Verify the next/last buttons are disabled on last page
			bbCtrl.last();
			System.assertEquals(false, bbCtrl.hasNext);

			// Verify the previous/first buttons are disabled on first page
			bbCtrl.previous();
			bbCtrl.first();
			System.assertEquals(false, bbCtrl.hasPrevious);

			// Verify the Quantity has been kept on page navigation
			bouquetFlowers = bbCtrl.getBouquetFlowers();
			System.assertEquals(8, bouquetFlowers[0].bloom.Quantity__c);

			// Move to next
			bbCtrl.next();
			bouquetFlowers = bbCtrl.getBouquetFlowers();
			bouquetFlowers[0].bloom.Quantity__c = 4;
			Product2 flower2 = bouquetFlowers[0].flower;

			// Test filter
			SelectOption[] families = bbCtrl.flowerFamilies;
			bbCtrl.flowerFamily = families[1].getValue(); // Select a family other than all and make sure the total flowers is less than 5
			// Change the flower family
			bbCtrl.changeFlowerFamily();
			System.assertEquals(bbCtrl.getBouquetFlowers().size(), [SELECT Id FROM Product2 WHERE Family = :bbCtrl.flowerFamily].size());

			// verify the totalCost logic 
			System.assertEquals(8 * flower1.Cost__c + 4 * flower2.Cost__c, bbCtrl.getTotalCost());
			// Verify the chart data
			List<BouquetBuilderController.SummaryPieData> pieData = bbCtrl.getSummaryPieData();
			System.assertEquals(2, pieData.size());
			System.assertEquals(2, bbCtrl.summaryPieChartColorSet.split(',').size());

		}		

	}

	// Test BouquetBuilder for new record
	@isTest
	static void testNewPage() {
		PageReference bbRef = Page.BouquetBuilder;
		Test.setCurrentPage(bbRef);

		System.runAs(getFloristUserA()) {
			Lead customer = [SELECT Street, FirstName, LastName FROM Lead LIMIT 1];

			ApexPages.StandardController stdCtrl = new ApexPages.StandardController(new Bouquet__c());
			BouquetBuilderController bbCtrl = new BouquetBuilderController(stdCtrl);

			// Create a new bouquet 
			Bouquet__c bouquet = (Bouquet__c)stdCtrl.getRecord();
			bouquet.Customer__c = customer.Id;
			bouquet.Deliver_To__c = customer.Street;
			bouquet.Message__c = 'Test Message';
			bouquet.Delivery_Date__c = Date.today();

			// Set bouquet flowers
			List<BouquetBuilderController.BouquetFlower> bouquetFlowers = bbCtrl.getBouquetFlowers();
			bouquetFlowers[0].bloom.Quantity__c = 8;
			Product2 flower1 = bouquetFlowers[0].flower;

			bbCtrl.next();

			bouquetFlowers = bbCtrl.getBouquetFlowers();
			bouquetFlowers[0].bloom.Quantity__c = 4;
			Product2 flower2 = bouquetFlowers[0].flower;

			PageReference viewPage = bbCtrl.save();

			// Verify the redirect after successful save
			System.assertEquals((new ApexPages.StandardController(bouquet)).view().getUrl(), viewPage.getUrl());
			// Check if the bouquet record has been created correctly
			System.assertEquals(customer.Street, [SELECT Deliver_To__c FROM Bouquet__c LIMIT 1].Deliver_To__c);
			// Check to see if the Most_Used_Color__c on customer has been udpated.
			System.assertEquals(flower1.Color__c, [SELECT Most_Used_Color__c FROM Lead WHERE Id = :customer.Id].Most_Used_Color__c);
			// Check the Inventory used
			System.assertEquals(8, [SELECT Inventory_Used__c FROM Product2 WHERE Id = :flower1.Id].Inventory_Used__c);
		}		

	}

	// Test BouquetBuilder for new record
	@isTest
	static void testNewPageWithException() {
		PageReference bbRef = Page.BouquetBuilder;
		Test.setCurrentPage(bbRef);

		System.runAs(getFloristUserA()) {
			Lead customer = [SELECT Street, FirstName, LastName FROM Lead LIMIT 1];

			ApexPages.StandardController stdCtrl = new ApexPages.StandardController(new Bouquet__c());
			BouquetBuilderController bbCtrl = new BouquetBuilderController(stdCtrl);

			// Create a new bouquet 
			Bouquet__c bouquet = (Bouquet__c)stdCtrl.getRecord();
			bouquet.Customer__c = customer.Id;
			bouquet.Deliver_To__c = customer.Street;
			bouquet.Message__c = 'Test Message';
			bouquet.Delivery_Date__c = Date.today();

			// Set bouquet flowers
			List<BouquetBuilderController.BouquetFlower> bouquetFlowers = bbCtrl.getBouquetFlowers();
			bouquetFlowers[0].bloom.Quantity__c = 8000; // This will thrown a DML exception by the validation rule
			Product2 flower1 = bouquetFlowers[0].flower;

			bbCtrl.next();

			bouquetFlowers = bbCtrl.getBouquetFlowers();
			bouquetFlowers[0].bloom.Quantity__c = 4;
			Product2 flower2 = bouquetFlowers[0].flower;

			PageReference viewPage = bbCtrl.save();

			// Verify the redirect after an unsucessful save
			System.assertEquals(null, viewPage);
			// Check if the bouquet record has not been created
			System.assertEquals(0, [SELECT Deliver_To__c FROM Bouquet__c].size());
		}		

	}

	// Test BoquetBuilder for existing record / Edit
	@isTest
	static void testEditPage() {
		PageReference bbRef = Page.BouquetBuilder;
		Test.setCurrentPage(bbRef);

		System.runAs(getFloristUserA()) {
			Lead customer = [SELECT Street, FirstName, LastName FROM Lead LIMIT 1];
			Product2 flowerBlue = [SELECT Name, Color__c, Initial_Inventory__c FROM Product2 WHERE Color__c='blue' LIMIT 1];
			Product2 flowerYellow = [SELECT Name, Color__c, Initial_Inventory__c FROM Product2 WHERE Color__c='yellow' LIMIT 1];
			Product2 flowerRed = [SELECT Name, Color__c, Initial_Inventory__c FROM Product2 WHERE Color__c='red' LIMIT 1];

			// Prepare the data for update
			Bouquet__c bouquet = new Bouquet__c();
			bouquet.Customer__c = customer.Id;
			bouquet.Deliver_To__c = customer.Street;
			bouquet.Message__c = 'Test Message';
			bouquet.Delivery_Date__c = Date.today();
			insert bouquet;

			Bloom__c bmBlue = new Bloom__c(Bouquet__c=bouquet.Id, Flower__c=flowerBlue.Id, Quantity__c=20);
			Bloom__c bmYellow = new Bloom__c(Bouquet__c=bouquet.Id, Flower__c=flowerYellow.Id, Quantity__c=10);
			Bloom__c bmRed = new Bloom__c(Bouquet__c=bouquet.Id, Flower__c=flowerRed.Id, Quantity__c=5);
			insert new List<Bloom__c> { bmBlue, bmYellow, bmRed };


			ApexPages.StandardController stdCtrl = new ApexPages.StandardController(bouquet);
			BouquetBuilderController bbCtrl = new BouquetBuilderController(stdCtrl);

			// Verify the bouquet is loaded
			System.assertEquals(bouquet.Customer__c, ((Bouquet__c)stdCtrl.getRecord()).Customer__c);
			// Verify the blooms and change it for update
			while (true) {
				List<BouquetBuilderController.BouquetFlower> bouquetFlowers = bbCtrl.getBouquetFlowers();
				for (BouquetBuilderController.BouquetFlower bm : bouquetFlowers) {
					if (bm.flower.Id == flowerBlue.Id) {
						System.assertEquals(20, bm.bloom.Quantity__c);
						bm.bloom.Quantity__c = flowerBlue.Initial_Inventory__c; // Use all the quanity to disable the flower
					}
					else if (bm.flower.Id == flowerYellow.Id) {
						System.assertEquals(10, bm.bloom.Quantity__c);
						bm.bloom.Quantity__c = 0; // Set to zero to remove the flower from bloom
					}
					else if (bm.flower.Id == flowerRed.Id) {
						System.assertEquals(5, bm.bloom.Quantity__c);
						bm.bloom.Quantity__c = 30; // Update the quantity
					}
				}
				if (bbCtrl.hasNext)
					bbCtrl.next();
				else
					break;
			} 
			// Set the value for update on bouquet
			bouquet = ((Bouquet__c)stdCtrl.getRecord());
			bouquet.Message__c = 'Test Message 2';

			PageReference viewPage = bbCtrl.save();

			// Verify the bouquet record
			System.assertEquals(bouquet.Message__c, [SELECT Message__c FROM Bouquet__c WHERE Id = :bouquet.Id].Message__c);
			Map<Id, Bloom__c> bmMap = new Map<Id, Bloom__c>();
			for (Bloom__c bm : [SELECT Id, Flower__c, Quantity__c FROM Bloom__c WHERE Bouquet__c=:bouquet.Id]) {
				bmMap.put(bm.Flower__c, bm);
			}
			System.assert(bmMap.containsKey(flowerBlue.Id));
			System.assert(bmMap.containsKey(flowerRed.Id));
			// Verify the flowerYellow has been removed
			System.assert(!bmMap.containsKey(flowerYellow.Id)); 

			// Verify the quantity of flowerRed has been updated
			bmRed = bmMap.get(flowerRed.Id);
			System.assertEquals(30, bmRed.Quantity__c);

			// Verify flowerBlue has been disabled beause the invertory is zero
			System.assertEquals(false, [SELECT IsActive FROM Product2 WHERE Id = :flowerBlue.Id].IsActive);
			// Verify the yellow flower's inventory has been reset
			System.assertEquals(0, [SELECT Inventory_Used__c FROM Product2 WHERE Id=:flowerYellow.Id].Inventory_Used__c); // 
			// Verify the most used color
			System.assertEquals(flowerBlue.Color__c, [SELECT Most_Used_Color__c FROM Lead WHERE Id = :customer.Id].Most_Used_Color__c);
			
		}		

	}

	// Test the bulk data DMLs
	@isTest
	static void testBulkUpsert() {
		List<Bouquet__c> bqList = new List<Bouquet__c>();
		List<Product2> flowers = [SELECT Name, Family, Color__c, Cost__c FROM Product2 LIMIT 100];
		List<Lead> customers = [SELECT Id, Street FROM Lead LIMIT 100];
		Set<Id> customerIds = new Map<Id, Lead>(customers).keySet();
		Integer index = 1;
		for (Lead customer : customers) {
			Bouquet__c bq = new Bouquet__c(
				Customer__c = customer.Id,
				Deliver_To__c = customer.Street,
				Delivery_Date__c = Date.today(),
				Message__c = 'Test Message ' + String.valueOf(index)
				);
			bqList.add(bq);

			index += 1;
		}

		// Bulk insert of bouquet
		insert bqList;
		bqList = [SELECT Customer__c, Customer__r.Street, Deliver_To__c, Delivery_Date__c, Message__c FROM Bouquet__c LIMIT 100];
		System.assertEquals(customers.size(), bqList.size());
		System.assertEquals(bqList[0].Customer__r.Street, bqList[0].Deliver_To__c);
		System.assertEquals(Date.today(), bqList[0].Delivery_Date__c);

		// Bulk update of bouquet
		for (Bouquet__c bq : bqList) {
			bq.Message__c = 'Update Message';
		}
		update bqList;
		bqList = [SELECT Customer__c, Customer__r.Street, Deliver_To__c, Delivery_Date__c, Message__c FROM Bouquet__c LIMIT 100];
		System.assertEquals('Update Message', bqList[0].Message__c);

		// Verify the Most_Used_Color__c is empty 
		System.assertEquals(customers.size(), [SELECT Id FROM Lead WHERE Most_Used_Color__c=NULL AND Id IN :customerIds].size());

		// Bulk insert of Bloom
		Integer fIdx = 0;
		Integer fCount = flowers.size();
		List<Bloom__c> bmList = new List<Bloom__c>();
		for (Bouquet__c bq : bqList) {
			if (fIdx == fCount) fIdx = 0;
			Product2 flower1 = flowers[fIdx++];
			Bloom__c bm1 = new Bloom__c(
				Bouquet__c = bq.Id,
				Flower__c = flower1.Id,
				Quantity__c = 1
				);

			if (fIdx == fCount) fIdx = 0;
			Product2 flower2 = flowers[fIdx++];
			Bloom__c bm2 = new Bloom__c(
				Bouquet__c = bq.Id,
				Flower__c = flower2.Id,
				Quantity__c = 1
				);

			bmList.add(bm1);
			bmList.add(bm2);
		}

		insert bmList;
		// Verify to the right amount of Bloom__c records have been created;
		System.assertEquals(bqList.size() * 2, [SELECT Id FROM Bloom__c LIMIT 500].size()); 

		// Bulk update and remove of Blooms
		List<Bloom__c> bmListUpdate = new List<Bloom__c>();
		List<Bloom__c> bmListRemove = new List<Bloom__c>();
		for (Bouquet__c bq : [SELECT Customer__c, (SELECT Id FROM Blooms__r) FROM Bouquet__c LIMIT 100]) {
			Bloom__c bm1 = bq.Blooms__r[0];
			Bloom__c bm2 = bq.Blooms__r[1];

			bm1.Quantity__c = 2;
			bmListUpdate.add(bm1);
			bmListRemove.add(bm2);
		}

		update bmListUpdate;
		delete bmListRemove;

		bmList = [SELECT Id, Quantity__c, Flower__c, Bouquet__c, Flower__r.Color__c, Bouquet__r.Customer__r.Most_Used_Color__c FROM Bloom__c LIMIT 500];
		System.assertEquals(customers.size(), bmList.size());  // Only one bloom per bouquet, the total number of blooms should be the same as bouquet/customer.
		System.assertEquals(2, bmList[0].Quantity__c);
		System.assertEquals(bmList[0].Bouquet__r.Customer__r.Most_Used_Color__c, bmList[0].Flower__r.Color__c); // Verify the most used color

		// Verify Inventory used summary field
		Product2 flower = [SELECT Initial_Inventory__c, Inventory_Used__c FROM Product2 WHERE Id = :bmList[0].Flower__c];
		Integer totalUsed = 0;
		for (Bloom__c bm : [SELECT Quantity__c FROM Bloom__c WHERE Flower__c = :flower.Id]) {
			totalUsed += (Integer)bm.Quantity__c;
		}
		System.assertEquals(totalUsed, flower.Inventory_Used__c);
	}
}