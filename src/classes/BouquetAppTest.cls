// Test class for Bouquet Application
@isTest
private class BouquetAppTest {
	@testSetup
	static void setUpTestData() {
		List<Lead> customers = Test.loadData(Lead.SObjectType, 'TestData_Customers');
		List<Product2> flowers = Test.loadData(Product2.SObjectType, 'TestData_Flowers');
		//System.debug('SetupData-customers: ' + JSON.serialize(customers));
		//System.debug('SetupData-flowers: ' + JSON.serialize(flowers));
	}

	// Simplify the method to get existing user. If will fail if the user name is changed.
	// The better option is to create the new user and assign the Inventory Manager profile
	static User getInventoryManagerUser() {
		User u = [SELECT Name FROM User WHERE FirstName='Irene' AND LastName='Inventory'];
		System.debug('Running User: ' + JSON.serialize(u));

		return u;
	}

	// Simplify the method to get existing user. If will fail if the user name is changed.
	// The better option is to create the new user and assign the Florist profile
	static User getFloristUser() {
		User u = [SELECT Name FROM User WHERE FirstName='Fred' AND LastName='Florist'];

		System.debug('Running User: ' + JSON.serialize(u));
		return u;
	}

	// Test the Most_Used_Color__c and Inventory_Used__c fields
	@isTest
	static void testAutoLogic() {
		System.runAs(getFloristUser()) {
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


	// Notice, the test static resource data file cannot be changed otherwise the test might be broken
	// It's better to split the following test method to multiple methods
	@isTest
	static void testBouquetBuilderController() {
		PageReference bbRef = Page.BouquetBuilder;
		Test.setCurrentPage(bbRef);

		System.runAs(getFloristUser()) {
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

			// Test the navigation
			// Move to next page to make sure the selected flower and quantity are remembered
			bbCtrl.next();
			System.assertEquals(true, bbCtrl.hasPrevious);
			System.assertEquals(true, bbCtrl.hasNext);
			System.assertEquals(2, bbCtrl.getPageNumber());
			System.assertEquals(5, bbCtrl.getPageCount());


			bouquetFlowers = bbCtrl.getBouquetFlowers();
			bouquetFlowers[0].bloom.Quantity__c = 4;
			Product2 flower2 = bouquetFlowers[0].flower;

			// Navigate
			bbCtrl.previous();
			bbCtrl.last();
			System.assertEquals(false, bbCtrl.hasNext);
			bbCtrl.first();
			System.assertEquals(false, bbCtrl.hasPrevious);

			// verify the totalCost logic 
			System.assertEquals(8 * flower1.Cost__c + 4 * flower2.Cost__c, bbCtrl.getTotalCost());
			// Verify the chart data
			List<BouquetBuilderController.SummaryPieData> pieData = bbCtrl.getSummaryPieData();
			System.assertEquals(2, pieData.size());
			System.assertEquals(2, bbCtrl.summaryPieChartColorSet.split(',').size());

			// Test filter
			SelectOption[] families = bbCtrl.flowerFamilies;
			bbCtrl.flowerFamily = families[1].getValue(); // Select a family other than all
			// Change the flower family
			bbCtrl.changeFlowerFamily();
			System.assertEquals(bbCtrl.getBouquetFlowers().size(), [SELECT Id FROM Product2 WHERE Family = :bbCtrl.flowerFamily].size());


			PageReference viewPage = bbCtrl.save();

			// Verify the redirect after successful save
			System.assertEquals((new ApexPages.StandardController(bouquet)).view().getUrl(), viewPage.getUrl());
			// Check if the bouquet record has been created correctly
			System.assertEquals(customer.Street, [SELECT Deliver_To__c FROM Bouquet__c LIMIT 1].Deliver_To__c);
			// Check to see if the Most_Used_Color__c on customer has been udpated.
			System.assertEquals(flower1.Color__c, [SELECT Most_Used_Color__c FROM Lead WHERE Id = :customer.Id].Most_Used_Color__c);
			// Check the Inventory used
			System.assertEquals(8, [SELECT Inventory_Used__c FROM Product2 WHERE Id = :flower1.Id].Inventory_Used__c);

			// Test Update
			// Set the flower1 to inactive
			flower1.Inventory_Used__c = flower1.Initial_Inventory__c;
			update flower1;
			System.assertEquals(false, [SELECT IsActive FROM Product2 WHERE Id = :flower1.Id].IsActive);

			bouquet = [SELECT Name, Customer__c, Deliver_To__c, Delivery_Date__c, Message__c FROM Bouquet__c LIMIT 1];
			stdCtrl = new ApexPages.StandardController(bouquet);
			bbCtrl = new BouquetBuilderController(stdCtrl);

			bouquet = (Bouquet__c)stdCtrl.getRecord();
			bouquet.Message__c = 'Test Message 2';

			// Verify the inactive product2 is listed
			bouquetFlowers = bbCtrl.getBouquetFlowers();
			System.assertEquals(flower1.Id, bouquetFlowers[0].flower.Id);
			System.assertEquals(false, bouquetFlowers[0].flower.IsActive);
			System.assertEquals(8, bouquetFlowers[0].bloom.Quantity__c);

			// Move the next page
			bbCtrl.next();
			bouquetFlowers = bbCtrl.getBouquetFlowers();
			System.assertEquals(4, bouquetFlowers[0].bloom.Quantity__c); // Check the loading result.
			bouquetFlowers[0].bloom.Quantity__c = 0; // Set to 0 to remove the product

			bbCtrl.next();
			bouquetFlowers = bbCtrl.getBouquetFlowers();
			bouquetFlowers[0].bloom.Quantity__c = 16;
			Product2 flower3 = bouquetFlowers[0].flower;

			viewPage = bbCtrl.save();
			// Verify the update on Bouquet Object
			System.assertEquals(bouquet.Message__c, [SELECT Message__c FROM Bouquet__c WHERE Id = :bouquet.Id].Message__c);
			Map<Id, Bloom__c> bmMap = new Map<Id, Bloom__c>();
			for (Bloom__c bm : [SELECT Id, Flower__c, Quantity__c FROM Bloom__c WHERE Bouquet__c=:bouquet.Id]) {
				bmMap.put(bm.Flower__c, bm);
			}
			System.assert(bmMap.containsKey(flower1.Id));
			System.assert(!bmMap.containsKey(flower2.Id));
			Bloom__c bm3 = bmMap.get(flower3.Id);
			System.assertEquals(16, bm3.Quantity__c);

			System.assertEquals(0, [SELECT Inventory_Used__c FROM Product2 WHERE Id=:flower2.Id].Inventory_Used__c); // 
			System.assertEquals(flower3.Color__c, [SELECT Most_Used_Color__c FROM Lead WHERE Id = :customer.Id].Most_Used_Color__c);

			System.debug(JSON.serialize([SELECT Name, Quantity__c, Flower__c, Bouquet__c FROM Bloom__c]));
			
		}		

	}

}