public with sharing class BouquetBuilderController {
	final static String FlowerFamily_AnyType = '--Any Type--';
	final static Integer CurrentPageSize = 5;

	// The flowers for the current bouquet to choose
	public with sharing class BouquetFlower {
		public Bloom__c bloom { get; set; }
		public Product2 flower { get; set; }
		public BouquetFlower(Product2 flower, Integer quantity) {
			if (quantity == null) quantity = 0;

			this.flower = flower;
			this.bloom = new Bloom__c(Quantity__c = quantity, Flower__r = flower);
		}
	}

	// Data class for the Pie Chart
	public with sharing class SummaryPieData {
		public String color { get; set; }
		// Make it transient to reduce the size of viewstate 
		transient public String colorCode { get; set; }
		public Integer quantity { get; set; }

		public SummaryPieData(Product2 flower, Integer quantity) {
			this.color = flower.Color__c;
			this.colorCode = flower.HTML_Color_Code__c;
			this.quantity = quantity;
		}

	}

	// Current Bouquet__c Object
	final Bouquet__c bouquet;
	// Available flowers for the current bouquet on the current page
	List<BouquetFlower> bouquetFlowers;
	// Flower Id -> Bloom__c Id Map for the current existing bouquet. 
	// This map stores the original blooms for the current bouquet.
	final Map<Id, Bloom__c> flowerIdBloomMap;

	// flower Id -> Quantity Map, selected flower Id -> quantity map
	public Map<Id, Integer> flowerQuantityMap;
	// selected flower Id -> flower map
	public Map<Id, Product2> flowerMap;



	public String flowerFamily { get; set; }
	public SelectOption[] flowerFamilies {
		get {
			System.debug(LoggingLevel.DEBUG, 'Enter flowerFamilies-get');
	
			List<SelectOption> options = new List<SelectOption> {
				new SelectOption(FlowerFamily_AnyType, FlowerFamily_AnyType)
			};

			for (Schema.PicklistEntry pe : Product2.Family.getDescribe().getPicklistValues()) {
				options.add(new SelectOption(pe.getValue(), pe.getValue()));
			}

			System.debug(LoggingLevel.DEBUG, 'Exit flowerFamilies-get');

			return options;
		}
	}

	// Standard List Controller for the flowers in bouquet to select
	public ApexPages.StandardSetController setCon {
		get {
			if (setCon == null) {
				setCon = createStandardSetController();
			}

			return setCon;
		}
		set;
	}

	// The available flowers for the current page
	public BouquetFlower[]  getBouquetFlowers() {
		System.debug(LoggingLevel.DEBUG, 'Enter getBouquetFlowers()');

		bouquetFlowers = new List<BouquetFlower>();
		for (Product2 flower : (Product2[])setCon.getRecords()) {
			bouquetFlowers.add(new BouquetFlower(flower, Integer.valueOf(this.flowerQuantityMap.get(flower.Id))));
		}

		System.debug(LoggingLevel.DEBUG, 'Exit getBouquetFlowers()');
		return bouquetFlowers;
	}

	// 
	public String summaryPieChartColorSet { get; set; }
	public SummaryPieData[] getSummaryPieData() {
		System.debug(LoggingLevel.DEBUG, 'Enter getSummaryPieData()');

		System.debug('flowerMap: ' + JSON.serialize(this.flowerMap));
		System.debug('flowerQuantityMap: ' + JSON.serialize(this.flowerQuantityMap));

		Map<String, SummaryPieData> colorPieDataMap = new Map<String, SummaryPieData>();
		for (Id flowerId : this.flowerQuantityMap.keySet()) {
			Product2 flower = this.flowerMap.get(flowerId);
			Integer quantity = this.flowerQuantityMap.get(flowerId);

			String color = flower.Color__c;
			SummaryPieData pieData = colorPieDataMap.get(color);
			if (pieData == null) {
				pieData = new SummaryPieData(flower, quantity);
				colorPieDataMap.put(color, pieData);
			} else {
				pieData.quantity += quantity;
			}
		}

		List<String> colors = new List<String>();
		for (SummaryPieData pieData : colorPieDataMap.values()) {
			colors.add(pieData.colorCode);
		}

		summaryPieChartColorSet = String.join(colors, ',');

		System.debug(LoggingLevel.DEBUG, 'Exit getSummaryPieData()');

		return colorPieDataMap.values();
	}

	// 
	// Performance wise, the loop can be merged with SummaryPieData. 
	public Decimal getTotalCost() {
		System.debug(LoggingLevel.DEBUG, 'Enter getTotalCost()');

		Decimal cost = 0;
		for (Id flowerId : this.flowerQuantityMap.keySet()) {
			Product2 flower = this.flowerMap.get(flowerId);
			Integer quantity = this.flowerQuantityMap.get(flowerId);

			cost += (quantity * flower.Cost__c);
		}

		System.debug(LoggingLevel.DEBUG, 'Exit getTotalCost()');

		return cost;
	}


	// Controller constructor
    public BouquetBuilderController(ApexPages.StandardController controller) {
		System.debug(LoggingLevel.DEBUG, 'Enter BouquetBuilderController()');

    	this.flowerFamily = FlowerFamily_AnyType;
    	this.bouquet = (Bouquet__c)controller.getRecord();
    	this.flowerQuantityMap = new Map<Id, Integer>();
    	this.flowerMap = new Map<Id, Product2>();
    	this.flowerIdBloomMap = new Map<Id, Bloom__c>();

    	this.bouquetFlowers = new List<BouquetFlower>(); 

    	if (this.bouquet.Id != null) {
			for (Bloom__c bl : [SELECT Flower__c, Quantity__c, Flower__r.Name, Flower__r.Family, Flower__r.IsActive, Flower__r.Color__c, Flower__r.HTML_Color_Code__c, Flower__r.Cost__c, Flower__r.Initial_Inventory__c, Flower__r.Inventory_Remaining__c, Flower__r.Inventory_Used__c FROM Bloom__c WHERE Bouquet__c = :bouquet.Id]) {
				this.flowerQuantityMap.put(bl.Flower__c, (Integer)bl.Quantity__c);
				this.flowerMap.put(bl.Flower__c, bl.Flower__r);
				// Technically it's possible the same flower can be selected multiple times for one bouquet.
				// I ignore the above posibility to simplify the implementation
				this.flowerIdBloomMap.put(bl.Flower__c, bl); 
			}
    	}

		System.debug(LoggingLevel.DEBUG, 'Exit BouquetBuilderController()');
    }


    // Return true if there's error on page level
    //public Boolean getHasErrors() {
    //	return ApexPages.hasMessages(ApexPages.Severity.Error);
    //}

    // returns the page number of the current page set
    public Integer getPageNumber() {
        return setCon.getPageNumber();
    }

    public Integer getPageCount() {
    	return (Integer)Math.ceil(setCon.getResultSize() * 1.0 / CurrentPageSize);
    }

	public Boolean hasNext {
		get { return setCon.getHasNext(); }
		set;
	}

	public Boolean hasPrevious {
		get { return setCon.getHasPrevious(); }
		set;
	}

    // returns the first page of records
    public void first() {
     	updateBouquetFlowers();
        setCon.first();
    }
    
    // returns the last page of records
    public void last() {
     	updateBouquetFlowers();
        setCon.last();
    }

    // returns the previous page of records
    public void previous() {
     	updateBouquetFlowers();
        setCon.previous();
    }

    // returns the next page of records
    public void next() {
     	updateBouquetFlowers();
        setCon.next();
    }


	public void changeFlowerFamily() {
		System.debug(LoggingLevel.DEBUG, 'Enter changeFlowerFamily()');

    	//System.debug(ApexPages.hasMessages());
    	// re-initialize the StandardSetController because the query criteria has been changed.
		setCon = createStandardSetController();
		// Always move to the first page
    	first();

		System.debug(LoggingLevel.DEBUG, 'Exit changeFlowerFamily()');
    }

    // Create StandardSetController for Bouquet flowers for the pagniation
    ApexPages.StandardSetController createStandardSetController() {
		System.debug(LoggingLevel.DEBUG, 'Enter createStandardSetController()');


    	ApexPages.StandardSetController ctrl;
    	if (flowerFamily == FlowerFamily_AnyType) {
	    	ctrl = new ApexPages.StandardSetController(
				Database.getQueryLocator([SELECT Name, Family, IsActive, Color__c, Cost__c, HTML_Color_Code__c, Initial_Inventory__c, Inventory_Remaining__c, Inventory_Used__c 
					FROM Product2 
					WHERE Id IN :this.flowerQuantityMap.keySet() OR (IsActive=TRUE AND Inventory_Remaining__c > 0)
					ORDER BY Cost__c, Color__c])
				);
	    } else {
	    	ctrl = new ApexPages.StandardSetController(
				Database.getQueryLocator([SELECT Name, Family, IsActive, Color__c, Cost__c, HTML_Color_Code__c, Initial_Inventory__c, Inventory_Remaining__c, Inventory_Used__c 
					FROM Product2 
					WHERE (Id IN :this.flowerQuantityMap.keySet() OR (IsActive=TRUE AND Inventory_Remaining__c > 0)) AND Family = :flowerFamily
					ORDER BY Cost__c, Color__c])
				);
	    }
		ctrl.setPageSize(CurrentPageSize);

		System.debug(LoggingLevel.DEBUG, 'Exit createStandardSetController()');

		return ctrl;
    }

 
    void updateBouquetFlowers() {
		System.debug(LoggingLevel.DEBUG, 'Enter updateBouquetFlowers()');
		System.debug(JSON.serialize(bouquetFlowers));

    	for (BouquetFlower bf : bouquetFlowers) {
    		if (bf.bloom.Quantity__c != null && bf.bloom.Quantity__c > 0) {
    			this.flowerQuantityMap.put(bf.flower.Id, Integer.valueOf(bf.bloom.Quantity__c));
    			this.flowerMap.put(bf.flower.Id, bf.flower);
    		} else {
    			this.flowerQuantityMap.remove(bf.flower.Id);
    			this.flowerMap.remove(bf.flower.Id);
    		}
    	}

    	System.debug(JSON.serialize(this.flowerQuantityMap));
    	System.debug(JSON.serialize(this.flowerMap));
		System.debug(LoggingLevel.DEBUG, 'Exit updateBouquetFlowers()');
    }

	public PageReference save() {
		System.debug(LoggingLevel.DEBUG, 'Enter save()');
		PageReference successPage = null; 

		updateBouquetFlowers();

		Boolean isUpdate = bouquet.Id != null;
		Set<Id> affectFlowerIds = new Set<Id>();

		try {
			// Disable the Bloom trigger.
			BouquetService.disableBloomTriggerLogic = true;

			if (isUpdate) {
				update bouquet;

				List<Bloom__c> insertList = new List<Bloom__c>();
				List<Bloom__c> updateList = new List<Bloom__c>();
				Map<Id, Bloom__c> originalBloomMap = flowerIdBloomMap.clone();
				for (Id flowerId : flowerQuantityMap.keySet()) {
					Integer quantity = flowerQuantityMap.get(flowerId);

					Bloom__c bm = new Bloom__c(
						Bouquet__c = bouquet.Id,
						Flower__c = flowerId,
						Quantity__c = quantity
						);

					if (originalBloomMap.containsKey(flowerId)) {
						// Update existing bloom
						bm.Id = originalBloomMap.get(flowerId).Id; // retrieve the orginal bloom for update
						updateList.add(bm);
						originalBloomMap.remove(flowerId);
					} else {
						insertList.add(bm);
					}
				}

				affectFlowerIds.addAll(flowerQuantityMap.keySet());
				affectFlowerIds.addAll(originalBloomMap.keySet());


				List<Bloom__c> removeList = originalBloomMap.values(); // The updated items have been removed. The remaining will be the items to delete
				if (insertList.size() > 0) insert insertList;
				if (updateList.size() > 0) update updateList;
				if (removeList.size() > 0) delete removeList;
			}
			else {
				insert bouquet;

				List<Bloom__c> bmList = new List<Bloom__c>();
				for (Id flowerId : flowerQuantityMap.keySet()) {
					Integer quantity = flowerQuantityMap.get(flowerId);
					//Product2 flower = flowerMap.get(flowerId);

					Bloom__c bm = new Bloom__c(
						Bouquet__c = bouquet.Id,
						Flower__c = flowerId,
						Quantity__c = quantity
						);

					bmList.add(bm);
				}

				// Insert bouquet flowers (Bloom__c)
				insert bmList;

				affectFlowerIds.addAll(flowerQuantityMap.keySet());
			}

			BouquetService service = new BouquetService();
			service.updateMostUsedColorForCustomers(new Set<Id> { bouquet.Customer__c });
			service.updateUsedInventoryForFlowers(affectFlowerIds);

			successPage = new ApexPages.StandardController(bouquet).view();
		} catch (Exception ex) {
			if (!isUpdate) 
				bouquet.Id = null; 

			ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, ex.getMessage()));

		} finally {
			BouquetService.disableBloomTriggerLogic = false; // re-enable it
		}


		System.debug(LoggingLevel.DEBUG, 'Exit save()');

		return successPage;
		//return null;
	}
}