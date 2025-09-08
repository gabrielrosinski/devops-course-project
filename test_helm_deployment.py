#!/usr/bin/env python3
"""
Helm Deployment Test Suite for QuakeWatch
Tests Helm chart deployment and validates application functionality
"""

import subprocess
import time
import json
import sys
import os
import requests
import pytest
from typing import Dict, List, Optional


class HelmDeploymentTest:
    def __init__(self, release_name: str = "quakewatch-test", namespace: str = "default"):
        self.release_name = release_name
        self.namespace = namespace
        self.helm_chart_path = "quackwatch-helm/"
        self.timeout = 300  # 5 minutes

    def run_command(self, cmd: List[str], check: bool = True) -> subprocess.CompletedProcess:
        """Execute shell command and return result"""
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, check=check)
            return result
        except subprocess.CalledProcessError as e:
            print(f"Command failed: {' '.join(cmd)}")
            print(f"Return code: {e.returncode}")
            print(f"STDOUT: {e.stdout}")
            print(f"STDERR: {e.stderr}")
            raise

    def test_helm_install(self):
        """Test Helm chart installation"""
        print("🔹 Installing Helm chart...")
        
        # Install or upgrade Helm release
        cmd = [
            "helm", "upgrade", "--install", self.release_name, 
            self.helm_chart_path,
            "--namespace", self.namespace,
            "--create-namespace",
            "--wait", "--timeout=5m"
        ]
        
        result = self.run_command(cmd)
        assert result.returncode == 0, f"Helm install failed: {result.stderr}"
        print("✅ Helm chart installed successfully")

    def test_deployment_status(self):
        """Test deployment status and readiness"""
        print("🔹 Checking deployment status...")
        
        # Get deployment status - deployment name is always quackwatch-helm
        cmd = ["kubectl", "get", "deployment", "quackwatch-helm", 
               "-n", self.namespace, "-o", "json"]
        result = self.run_command(cmd)
        
        deployment = json.loads(result.stdout)
        
        # Check deployment exists and has desired replicas
        assert deployment["status"]["replicas"] > 0, "No replicas found"
        assert deployment["status"]["readyReplicas"] == deployment["status"]["replicas"], \
            "Not all replicas are ready"
        
        print(f"✅ Deployment has {deployment['status']['readyReplicas']} ready replicas")

    def test_pods_running(self):
        """Test that pods are running and healthy"""
        print("🔹 Checking pod status...")
        
        # Wait for pods to be running
        max_attempts = 30
        for attempt in range(max_attempts):
            cmd = ["kubectl", "get", "pods", "-l", "app.kubernetes.io/instance=quackwatch-helm",
                   "-n", self.namespace, "-o", "json"]
            result = self.run_command(cmd)
            pods = json.loads(result.stdout)
            
            if not pods["items"]:
                time.sleep(2)
                continue
                
            all_running = True
            for pod in pods["items"]:
                if pod["status"]["phase"] != "Running":
                    all_running = False
                    break
            
            if all_running:
                print(f"✅ All {len(pods['items'])} pods are running")
                return pods["items"]
            
            print(f"⏳ Waiting for pods to be ready... (attempt {attempt + 1}/{max_attempts})")
            time.sleep(2)
        
        raise AssertionError("Pods did not reach Running state within timeout")

    def test_service_exists(self):
        """Test that service is created and accessible"""
        print("🔹 Checking service...")
        
        cmd = ["kubectl", "get", "service", "quackwatch-helm",
               "-n", self.namespace, "-o", "json"]
        result = self.run_command(cmd)
        
        service = json.loads(result.stdout)
        assert service["spec"]["ports"], "Service has no ports defined"
        
        print(f"✅ Service exists with {len(service['spec']['ports'])} ports")
        return service

    def test_configmap_mount(self):
        """Test ConfigMap is properly mounted"""
        print("🔹 Verifying ConfigMap mount...")
        
        # Get first pod
        cmd = ["kubectl", "get", "pods", "-l", "app.kubernetes.io/instance=quackwatch-helm",
               "-n", self.namespace, "-o", "jsonpath={.items[0].metadata.name}"]
        result = self.run_command(cmd)
        pod_name = result.stdout.strip()
        
        if not pod_name:
            raise AssertionError("No pods found for ConfigMap test")
        
        # Check if config directory exists
        cmd = ["kubectl", "exec", pod_name, "-n", self.namespace, "--", "ls", "/data"]
        result = self.run_command(cmd, check=False)
        
        if result.returncode == 0:
            print("✅ ConfigMap mounted successfully")
            
            # Try to read config file
            cmd = ["kubectl", "exec", pod_name, "-n", self.namespace, "--", "cat", "/data/earthquake.conf"]
            config_result = self.run_command(cmd, check=False)
            if config_result.returncode == 0:
                print("✅ Configuration file accessible")
            else:
                print("⚠️ Configuration file not found, but mount exists")
        else:
            print("⚠️ ConfigMap mount directory not found")

    def test_application_health(self):
        """Test application health endpoints"""
        print("🔹 Testing application health...")
        
        # Get pod name
        cmd = ["kubectl", "get", "pods", "-l", "app.kubernetes.io/instance=quackwatch-helm",
               "-n", self.namespace, "-o", "jsonpath={.items[0].metadata.name}"]
        result = self.run_command(cmd)
        pod_name = result.stdout.strip()
        
        if not pod_name:
            raise AssertionError("No pods found for health test")
        
        # Port forward in background
        port_forward_cmd = ["kubectl", "port-forward", pod_name, "8080:5000", "-n", self.namespace]
        port_forward_process = subprocess.Popen(port_forward_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        
        try:
            # Wait for port forward to be ready
            time.sleep(3)
            
            # Test health endpoints
            health_endpoints = ["/ping", "/health", "/status"]
            for endpoint in health_endpoints:
                try:
                    response = requests.get(f"http://localhost:8080{endpoint}", timeout=10)
                    if response.status_code == 200:
                        print(f"✅ Health endpoint {endpoint} responding")
                    else:
                        print(f"⚠️ Health endpoint {endpoint} returned {response.status_code}")
                except requests.RequestException as e:
                    print(f"⚠️ Health endpoint {endpoint} failed: {e}")
            
            # Test main application endpoint
            try:
                response = requests.get("http://localhost:8080/", timeout=10)
                if response.status_code == 200:
                    print("✅ Main application endpoint responding")
                else:
                    print(f"⚠️ Main endpoint returned {response.status_code}")
            except requests.RequestException as e:
                print(f"⚠️ Main application endpoint failed: {e}")
                
        finally:
            # Clean up port forward
            port_forward_process.terminate()
            port_forward_process.wait()

    def test_hpa_exists(self):
        """Test Horizontal Pod Autoscaler exists"""
        print("🔹 Checking HPA...")
        
        cmd = ["kubectl", "get", "hpa", "quackwatch-helm",
               "-n", self.namespace, "-o", "json"]
        result = self.run_command(cmd, check=False)
        
        if result.returncode == 0:
            hpa = json.loads(result.stdout)
            min_replicas = hpa["spec"]["minReplicas"]
            max_replicas = hpa["spec"]["maxReplicas"]
            print(f"✅ HPA configured: {min_replicas}-{max_replicas} replicas")
        else:
            print("⚠️ HPA not found or not configured")

    def cleanup(self):
        """Clean up test deployment"""
        print("🧹 Cleaning up test deployment...")
        
        cmd = ["helm", "uninstall", self.release_name, "-n", self.namespace]
        result = self.run_command(cmd, check=False)
        
        if result.returncode == 0:
            print("✅ Test deployment cleaned up")
        else:
            print("⚠️ Cleanup may have failed, check manually")

    def run_all_tests(self):
        """Run complete test suite"""
        print("🚀 Starting Helm Deployment Test Suite")
        print("=" * 50)
        
        try:
            self.test_helm_install()
            self.test_deployment_status()
            pods = self.test_pods_running()
            self.test_service_exists()
            self.test_configmap_mount()
            self.test_application_health()
            self.test_hpa_exists()
            
            print("=" * 50)
            print("✅ All tests completed successfully!")
            return True
            
        except Exception as e:
            print("=" * 50)
            print(f"❌ Test failed: {e}")
            return False
        
        finally:
            if os.getenv("CLEANUP", "true").lower() == "true":
                self.cleanup()


def main():
    """Main entry point for command line usage"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Test Helm deployment for QuakeWatch")
    parser.add_argument("--release-name", default="quakewatch-test", help="Helm release name")
    parser.add_argument("--namespace", default="default", help="Kubernetes namespace")
    parser.add_argument("--no-cleanup", action="store_true", help="Skip cleanup after tests")
    
    args = parser.parse_args()
    
    if args.no_cleanup:
        os.environ["CLEANUP"] = "false"
    
    test_suite = HelmDeploymentTest(args.release_name, args.namespace)
    success = test_suite.run_all_tests()
    
    sys.exit(0 if success else 1)


# Pytest integration
class TestHelmDeployment:
    """Pytest test class for CI/CD integration"""
    
    @classmethod
    def setup_class(cls):
        cls.test_suite = HelmDeploymentTest("quackwatch-helm", "default")
    
    @classmethod
    def teardown_class(cls):
        if os.getenv("CLEANUP", "true").lower() == "true":
            cls.test_suite.cleanup()
    
    def test_helm_install(self):
        self.test_suite.test_helm_install()
    
    def test_deployment_status(self):
        self.test_suite.test_deployment_status()
    
    def test_pods_running(self):
        self.test_suite.test_pods_running()
    
    def test_service_exists(self):
        self.test_suite.test_service_exists()
    
    def test_configmap_mount(self):
        self.test_suite.test_configmap_mount()
    
    def test_application_health(self):
        self.test_suite.test_application_health()
    
    def test_hpa_exists(self):
        self.test_suite.test_hpa_exists()


if __name__ == "__main__":
    main()