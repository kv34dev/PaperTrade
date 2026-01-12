import SwiftUI
import Charts
import Combine

// MARK: - Models
struct Asset: Identifiable, Codable {
    let id = UUID()
    let symbol: String
    let name: String
    let type: AssetType
    let basePrice: Double
    
    enum CodingKeys: String, CodingKey {
        case symbol, name, type, basePrice
    }
}

enum AssetType: String, Codable {
    case crypto = "Crypto"
    case forex = "Forex"
    case stock = "Stock"
    case index = "Index"
}

struct Position: Identifiable, Codable {
    let id: UUID
    let symbol: String
    let name: String
    let type: AssetType
    var amount: Double
    var avgPrice: Double
    
    init(asset: Asset, amount: Double, avgPrice: Double) {
        self.id = UUID()
        self.symbol = asset.symbol
        self.name = asset.name
        self.type = asset.type
        self.amount = amount
        self.avgPrice = avgPrice
    }
}

struct PricePoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let price: Double
}

// MARK: - ViewModel
class TradingViewModel: ObservableObject {
    @Published var balance: Double
    @Published var positions: [Position] = []
    @Published var prices: [String: Double] = [:]
    @Published var chartData: [PricePoint] = []
    @Published var initialCapital: Double
    
    private var timer: Timer?
    private var priceHistory: [String: [Double]] = [:]
    
    let assets: [Asset] = [
        Asset(symbol: "BTC/USD", name: "Bitcoin", type: .crypto, basePrice: 45000),
        Asset(symbol: "ETH/USD", name: "Ethereum", type: .crypto, basePrice: 2500),
        Asset(symbol: "EUR/USD", name: "Euro/Dollar", type: .forex, basePrice: 1.08),
        Asset(symbol: "GBP/USD", name: "Pound/Dollar", type: .forex, basePrice: 1.26),
        Asset(symbol: "AAPL", name: "Apple Inc.", type: .stock, basePrice: 185),
        Asset(symbol: "TSLA", name: "Tesla Inc.", type: .stock, basePrice: 242),
        Asset(symbol: "S&P500", name: "S&P 500", type: .index, basePrice: 4800),
        Asset(symbol: "NASDAQ", name: "NASDAQ", type: .index, basePrice: 15000)
    ]
    
    init() {
        self.balance = 10000
        self.initialCapital = 10000
        loadData()
        initializePrices()
        startPriceUpdates()
    }
    
    func initializePrices() {
        for asset in assets {
            prices[asset.symbol] = asset.basePrice
            priceHistory[asset.symbol] = [asset.basePrice]
        }
    }
    
    func startPriceUpdates() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updatePrices()
        }
    }
    
    func updatePrices() {
        for asset in assets {
            let currentPrice = prices[asset.symbol] ?? asset.basePrice
            let volatility: Double
            
            switch asset.type {
            case .crypto: volatility = 0.003
            case .forex: volatility = 0.0008
            case .stock: volatility = 0.0015
            case .index: volatility = 0.0012
            }
            
            // More chaotic price movement
            let trend = Double.random(in: -0.3...0.7) // Slight upward bias
            let randomWalk = (Double.random(in: 0...1) - 0.5) * 2
            let change = (trend * 0.3 + randomWalk * 0.7) * volatility
            
            let newPrice = currentPrice * (1 + change)
            prices[asset.symbol] = newPrice
            
            // Store price history
            if priceHistory[asset.symbol] == nil {
                priceHistory[asset.symbol] = []
            }
            priceHistory[asset.symbol]?.append(newPrice)
            if priceHistory[asset.symbol]?.count ?? 0 > 50 {
                priceHistory[asset.symbol]?.removeFirst()
            }
        }
    }
    
    func getChartData(for symbol: String) -> [PricePoint] {
        guard let history = priceHistory[symbol] else { return [] }
        return history.enumerated().map { index, price in
            PricePoint(timestamp: Date().addingTimeInterval(TimeInterval(index * 2)), price: price)
        }
    }
    
    func getPrice(for symbol: String) -> Double {
        prices[symbol] ?? assets.first(where: { $0.symbol == symbol })?.basePrice ?? 0
    }
    
    func executeBuy(asset: Asset, amount: Double) -> Bool {
        let price = getPrice(for: asset.symbol)
        let cost = amount * price
        
        guard cost <= balance else { return false }
        
        balance -= cost
        
        if let index = positions.firstIndex(where: { $0.symbol == asset.symbol }) {
            let existing = positions[index]
            let newAmount = existing.amount + amount
            let newAvgPrice = (existing.avgPrice * existing.amount + price * amount) / newAmount
            positions[index].amount = newAmount
            positions[index].avgPrice = newAvgPrice
        } else {
            positions.append(Position(asset: asset, amount: amount, avgPrice: price))
        }
        
        saveData()
        return true
    }
    
    func executeSell(asset: Asset, amount: Double) -> Bool {
        guard let index = positions.firstIndex(where: { $0.symbol == asset.symbol }),
              positions[index].amount >= amount else { return false }
        
        let price = getPrice(for: asset.symbol)
        balance += amount * price
        
        positions[index].amount -= amount
        if positions[index].amount < 0.00001 {
            positions.remove(at: index)
        }
        
        saveData()
        return true
    }
    
    func closePosition(position: Position) {
        let price = getPrice(for: position.symbol)
        balance += position.amount * price
        
        if let index = positions.firstIndex(where: { $0.id == position.id }) {
            positions.remove(at: index)
        }
        
        saveData()
    }
    
    func getPortfolioValue() -> Double {
        let positionsValue = positions.reduce(0.0) { sum, position in
            sum + position.amount * getPrice(for: position.symbol)
        }
        return balance + positionsValue
    }
    
    func getPnL() -> Double {
        getPortfolioValue() - initialCapital
    }
    
    func getPnLPercent() -> Double {
        (getPnL() / initialCapital) * 100
    }
    
    func resetPortfolio(newCapital: Double) {
        initialCapital = newCapital
        balance = newCapital
        positions = []
        saveData()
    }
    
    func saveData() {
        UserDefaults.standard.set(balance, forKey: "balance")
        UserDefaults.standard.set(initialCapital, forKey: "initialCapital")
        
        if let encoded = try? JSONEncoder().encode(positions) {
            UserDefaults.standard.set(encoded, forKey: "positions")
        }
    }
    
    func loadData() {
        balance = UserDefaults.standard.double(forKey: "balance")
        initialCapital = UserDefaults.standard.double(forKey: "initialCapital")
        
        if balance == 0 { balance = 10000 }
        if initialCapital == 0 { initialCapital = 10000 }
        
        if let data = UserDefaults.standard.data(forKey: "positions"),
           let decoded = try? JSONDecoder().decode([Position].self, from: data) {
            positions = decoded
        }
    }
    
    deinit {
        timer?.invalidate()
    }
}

// MARK: - Content View
struct ContentView: View {
    @StateObject private var viewModel = TradingViewModel()
    
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
            
            MarketsView()
                .tabItem {
                    Label("Markets", systemImage: "chart.line.uptrend.xyaxis")
                }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .environmentObject(viewModel)
    }
}

// MARK: - Home View
struct HomeView: View {
    @EnvironmentObject var viewModel: TradingViewModel
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Portfolio Header
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Portfolio Value")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.9))
                                
                                Text("$\(viewModel.getPortfolioValue(), specifier: "%.2f")")
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            Spacer()
                        }
                        
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Cash")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                                Text("$\(viewModel.balance, specifier: "%.2f")")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(12)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("P&L")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                                Text("\(viewModel.getPnL() >= 0 ? "+" : "")$\(viewModel.getPnL(), specifier: "%.2f") (\(viewModel.getPnLPercent(), specifier: "%.2f")%)")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(viewModel.getPnL() >= 0 ? .green.opacity(0.9) : .red.opacity(0.9))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(12)
                        }
                    }
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    
                    // Positions
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Open Positions")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.horizontal)
                        
                        if viewModel.positions.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "chart.xyaxis.line")
                                    .font(.system(size: 48))
                                    .foregroundColor(.gray.opacity(0.5))
                                
                                Text("No open positions")
                                    .font(.headline)
                                    .foregroundColor(.gray)
                                
                                Text("Start trading in Markets tab")
                                    .font(.subheadline)
                                    .foregroundColor(.gray.opacity(0.7))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            ForEach(viewModel.positions) { position in
                                PositionCard(position: position)
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Home")
        }
    }
}

// MARK: - Markets View
struct MarketsView: View {
    @EnvironmentObject var viewModel: TradingViewModel
    @State private var searchText = ""
    
    var filteredAssets: [Asset] {
        if searchText.isEmpty {
            return viewModel.assets
        }
        return viewModel.assets.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.symbol.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(filteredAssets) { asset in
                        NavigationLink(destination: AssetDetailView(asset: asset)) {
                            AssetCard(asset: asset)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Markets")
            .searchable(text: $searchText, prompt: "Search assets")
        }
    }
}

// MARK: - Asset Card
struct AssetCard: View {
    @EnvironmentObject var viewModel: TradingViewModel
    let asset: Asset
    
    var currentPrice: Double {
        viewModel.getPrice(for: asset.symbol)
    }
    
    var change: Double {
        currentPrice - asset.basePrice
    }
    
    var changePercent: Double {
        (change / asset.basePrice) * 100
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(asset.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(asset.type.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("$\(currentPrice, specifier: "%.2f")")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                HStack(spacing: 4) {
                    Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10))
                    Text("\(changePercent >= 0 ? "+" : "")\(changePercent, specifier: "%.2f")%")
                        .font(.caption)
                }
                .foregroundColor(change >= 0 ? .green : .red)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        .padding(.horizontal)
    }
}

// MARK: - Position Card
struct PositionCard: View {
    @EnvironmentObject var viewModel: TradingViewModel
    let position: Position
    @State private var showCloseAlert = false
    
    var currentPrice: Double {
        viewModel.getPrice(for: position.symbol)
    }
    
    var pnl: Double {
        (currentPrice - position.avgPrice) * position.amount
    }
    
    var pnlPercent: Double {
        ((currentPrice - position.avgPrice) / position.avgPrice) * 100
    }
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(position.symbol)
                        .font(.system(size: 16, weight: .semibold))
                    Text("\(position.amount, specifier: "%.6f") units")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("$\(currentPrice * position.amount, specifier: "%.2f")")
                        .font(.system(size: 16, weight: .semibold))
                    Text("\(pnl >= 0 ? "+" : "")$\(pnl, specifier: "%.2f") (\(pnlPercent >= 0 ? "+" : "")\(pnlPercent, specifier: "%.2f")%)")
                        .font(.caption)
                        .foregroundColor(pnl >= 0 ? .green : .red)
                }
            }
            
            Button(action: {
                showCloseAlert = true
            }) {
                Text("Close Position")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.red)
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        .padding(.horizontal)
        .alert("Close Position?", isPresented: $showCloseAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Close", role: .destructive) {
                viewModel.closePosition(position: position)
            }
        } message: {
            Text("Close \(position.symbol) position with \(pnl >= 0 ? "profit" : "loss") of $\(abs(pnl), specifier: "%.2f")?")
        }
    }
}

// MARK: - Asset Detail View
struct AssetDetailView: View {
    @EnvironmentObject var viewModel: TradingViewModel
    @Environment(\.dismiss) var dismiss
    let asset: Asset
    
    @State private var tradeAmount = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    var currentPrice: Double {
        viewModel.getPrice(for: asset.symbol)
    }
    
    var change: Double {
        currentPrice - asset.basePrice
    }
    
    var changePercent: Double {
        (change / asset.basePrice) * 100
    }
    
    var position: Position? {
        viewModel.positions.first(where: { $0.symbol == asset.symbol })
    }
    
    var chartData: [PricePoint] {
        viewModel.getChartData(for: asset.symbol)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Price Header
                VStack(spacing: 8) {
                    Text("$\(currentPrice, specifier: "%.2f")")
                        .font(.system(size: 36, weight: .bold))
                    
                    HStack(spacing: 4) {
                        Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                        Text("\(change >= 0 ? "+" : "")\(change, specifier: "%.2f") (\(changePercent >= 0 ? "+" : "")\(changePercent, specifier: "%.2f")%)")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(change >= 0 ? .green : .red)
                }
                .padding()
                
                // Chart
                    if !chartData.isEmpty {

                        let prices = chartData.map { $0.price }
                        let minPrice = prices.min() ?? 0
                        let maxPrice = prices.max() ?? 0
                        let padding = (maxPrice - minPrice) * 0.5

                        Chart {
                            ForEach(chartData) { point in
                                LineMark(
                                    x: .value("Time", point.timestamp),
                                    y: .value("Price", point.price)
                                )
                                .interpolationMethod(.linear) // ← углы
                                .foregroundStyle(change >= 0 ? .green : .red)
                            }

                            if let last = chartData.last {
                                PointMark(
                                    x: .value("Time", last.timestamp),
                                    y: .value("Price", last.price)
                                )
                                .symbolSize(90)
                                .foregroundStyle(change >= 0 ? .green : .red)
                            }
                        }
                        .frame(height: 300)
                        .chartYScale(domain: (minPrice - padding)...(maxPrice + padding))
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .padding()
                    }
                
                // Position Info
                if let pos = position {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your Position")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("\(pos.amount, specifier: "%.6f") units @ $\(pos.avgPrice, specifier: "%.2f")")
                            .font(.system(size: 16, weight: .semibold))
                        
                        let positionPnL = (currentPrice - pos.avgPrice) * pos.amount
                        Text("P&L: \(positionPnL >= 0 ? "+" : "")$\(positionPnL, specifier: "%.2f")")
                            .font(.system(size: 14))
                            .foregroundColor(positionPnL >= 0 ? .green : .red)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                
                // Trade Panel
                VStack(spacing: 16) {
                    TextField("Amount", text: $tradeAmount)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(.horizontal)
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            executeTrade(type: .buy)
                        }) {
                            Text("Buy")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .cornerRadius(12)
                        }
                        
                        Button(action: {
                            executeTrade(type: .sell)
                        }) {
                            Text("Sell")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.05), radius: 5)
                .padding()
            }
        }
        .navigationTitle(asset.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert(alertMessage, isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        }
    }
    
    enum TradeType {
        case buy, sell
    }
    
    func executeTrade(type: TradeType) {
        guard let amount = Double(tradeAmount), amount > 0 else {
            alertMessage = "Please enter a valid amount"
            showAlert = true
            return
        }
        
        let success: Bool
        if type == .buy {
            success = viewModel.executeBuy(asset: asset, amount: amount)
            if !success {
                alertMessage = "Insufficient balance"
                showAlert = true
            }
        } else {
            success = viewModel.executeSell(asset: asset, amount: amount)
            if !success {
                alertMessage = "Insufficient position"
                showAlert = true
            }
        }
        
        if success {
            tradeAmount = ""
        }
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @EnvironmentObject var viewModel: TradingViewModel
    @State private var newCapital = ""
    @State private var showResetAlert = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Initial Capital")) {
                    TextField("Amount", text: $newCapital)
                        .keyboardType(.decimalPad)
                    
                    Button(action: {
                        showResetAlert = true
                    }) {
                        Text("Reset Portfolio")
                            .foregroundColor(.red)
                    }
                }
                
                Section(footer: Text("Resetting will clear all positions and set new balance")) {
                    EmptyView()
                }
            }
            .navigationTitle("Settings")
            .alert("Reset Portfolio?", isPresented: $showResetAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    if let capital = Double(newCapital), capital > 0 {
                        viewModel.resetPortfolio(newCapital: capital)
                        newCapital = ""
                    }
                }
            } message: {
                Text("This will clear all your positions and reset your balance. This action cannot be undone.")
            }
        }
    }
}

#Preview {
    ContentView()
}
