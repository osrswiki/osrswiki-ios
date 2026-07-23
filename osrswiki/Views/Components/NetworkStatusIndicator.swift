//
//  NetworkStatusIndicator.swift
//  OSRS Wiki
//
//  Network status indicator component for showing connectivity status
//

import SwiftUI

struct NetworkStatusIndicator: View {
    @StateObject private var networkManager = NetworkManager.shared
    @State private var showingOfflineBanner = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Offline banner that slides down when connection is lost
            if !networkManager.isConnected && showingOfflineBanner {
                HStack {
                    Image(systemName: "wifi.slash")
                        .foregroundColor(.white)
                    
                    Text("No internet connection")
                        .font(.osrsCaption)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button("Dismiss") {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingOfflineBanner = false
                        }
                    }
                    .font(.osrsCaption)
                    .foregroundColor(.white.opacity(0.8))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.red)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onChange(of: networkManager.isConnected) { _, isConnected in
            if !isConnected {
                // Show offline banner when connection is lost
                withAnimation(.easeInOut(duration: 0.3)) {
                    showingOfflineBanner = true
                }
            } else {
                // Hide offline banner when connection is restored
                withAnimation(.easeInOut(duration: 0.3)) {
                    showingOfflineBanner = false
                }
            }
        }
    }
}

/// Compact network status indicator for use in other views
struct CompactNetworkStatusIndicator: View {
    @StateObject private var networkManager = NetworkManager.shared
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(networkManager.isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            
            Text(networkManager.isConnected ? "Online" : "Offline")
                .font(.osrsCaption)
                .foregroundColor(.secondary)
        }
    }
}

/// Network status badge for showing connection type
struct NetworkStatusBadge: View {
    @StateObject private var networkManager = NetworkManager.shared
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: networkManager.isConnected ? networkIconName : "wifi.slash")
                .font(.caption)
                .foregroundColor(networkManager.isConnected ? .green : .red)
            
            Text(statusText)
                .font(.osrsCaption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var networkIconName: String {
        switch networkManager.connectionType {
        case .wifi:
            return "wifi"
        case .cellular:
            return "antenna.radiowaves.left.and.right"
        case .wiredEthernet:
            return "network"
        case .loopback:
            return "network"
        case .other:
            return "network"
        case .none:
            return "network"
        @unknown default:
            return "network"
        }
    }
    
    private var statusText: String {
        if !networkManager.isConnected {
            return "Offline"
        }
        
        switch networkManager.connectionType {
        case .wifi:
            return "Wi-Fi"
        case .cellular:
            return "Cellular"
        case .wiredEthernet:
            return "Ethernet"
        case .loopback:
            return "Local"
        case .other:
            return "Online"
        case .none:
            return "Online"
        @unknown default:
            return "Online"
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        NetworkStatusIndicator()
        CompactNetworkStatusIndicator()
        NetworkStatusBadge()
    }
    .padding()
}