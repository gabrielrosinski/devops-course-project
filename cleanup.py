#!/usr/bin/env python3
"""
QuakeWatch Cleanup Script

Removes all resources deployed by build-deploy.sh:
- ArgoCD application and installation
- Application resources in default namespace
- Prometheus & Grafana monitoring stack
- Monitoring resources (alerts, dashboards, ServiceMonitor)
- Port-forward processes

Does NOT remove (to prevent breaking other apps):
- k3s installation or service
- Prometheus Operator CRDs (cluster-wide)
- metrics-server (may be used by other apps)
- kubectl config
- Helm repositories

Usage:
    python3 cleanup.py                  # Interactive mode with resource listing
    python3 cleanup.py --all            # Skip confirmations
    python3 cleanup.py --dry-run        # Show what would be deleted
    python3 cleanup.py --verbose        # Show all commands
"""

import subprocess
import sys
import time
import argparse
from typing import List, Tuple, Optional
from dataclasses import dataclass


@dataclass
class Resource:
    """Represents a Kubernetes resource"""
    type: str
    name: str
    namespace: str


class Colors:
    """ANSI color codes"""
    RED = '\033[91m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    RESET = '\033[0m'
    BOLD = '\033[1m'


class QuakeWatchCleanup:
    """Main cleanup class"""

    def __init__(self, args):
        self.args = args
        self.deleted_resources = []
        self.verbose = args.verbose
        self.dry_run = args.dry_run

    # ==================== Helper Methods ====================

    def print_header(self, message: str):
        """Print formatted header"""
        print(f"\n{Colors.BOLD}{Colors.CYAN}{'='*60}{Colors.RESET}")
        print(f"{Colors.BOLD}{Colors.CYAN}{message}{Colors.RESET}")
        print(f"{Colors.BOLD}{Colors.CYAN}{'='*60}{Colors.RESET}\n")

    def print_success(self, message: str):
        """Print success message"""
        print(f"{Colors.GREEN}✅ {message}{Colors.RESET}")

    def print_error(self, message: str):
        """Print error message"""
        print(f"{Colors.RED}❌ {message}{Colors.RESET}")

    def print_warning(self, message: str):
        """Print warning message"""
        print(f"{Colors.YELLOW}⚠️  {message}{Colors.RESET}")

    def print_info(self, message: str):
        """Print info message"""
        print(f"{Colors.BLUE}ℹ️  {message}{Colors.RESET}")

    def run_command(self, cmd: List[str], capture_output: bool = True) -> Tuple[int, str, str]:
        """Run command and return exit code, stdout, stderr"""
        if self.verbose:
            print(f"{Colors.CYAN}> {' '.join(cmd)}{Colors.RESET}")

        if self.dry_run and cmd[0] in ['kubectl', 'helm'] and any(x in cmd for x in ['delete', 'uninstall']):
            print(f"{Colors.YELLOW}[DRY-RUN] Would execute: {' '.join(cmd)}{Colors.RESET}")
            return 0, "", ""

        try:
            result = subprocess.run(cmd, capture_output=capture_output, text=True)
            return result.returncode, result.stdout, result.stderr
        except Exception as e:
            return 1, "", str(e)

    def confirm_action(self, message: str, default: bool = False) -> bool:
        """Ask user for confirmation"""
        if self.args.all:
            return True

        prompt = f"{Colors.YELLOW}? {message} [{('y/N', 'Y/n')[default]}]: {Colors.RESET}"
        response = input(prompt).strip().lower()
        return response in ['y', 'yes'] if response else default

    def namespace_exists(self, namespace: str) -> bool:
        """Check if namespace exists"""
        returncode, _, _ = self.run_command(['kubectl', 'get', 'namespace', namespace])
        return returncode == 0

    def resource_exists(self, resource_type: str, name: str, namespace: Optional[str] = None) -> bool:
        """Check if resource exists"""
        cmd = ['kubectl', 'get', resource_type, name]
        if namespace:
            cmd.extend(['-n', namespace])
        returncode, _, _ = self.run_command(cmd)
        return returncode == 0

    def helm_release_exists(self, release: str, namespace: str) -> bool:
        """Check if Helm release exists"""
        returncode, stdout, _ = self.run_command(['helm', 'list', '-n', namespace, '-q'])
        return returncode == 0 and release in stdout

    def delete_resource(self, resource_type: str, name: str, namespace: Optional[str] = None, wait: bool = False) -> bool:
        """Delete a Kubernetes resource"""
        cmd = ['kubectl', 'delete', resource_type, name, '--ignore-not-found=true']
        if namespace:
            cmd.extend(['-n', namespace])
        if wait:
            cmd.append('--wait=true')

        returncode, _, stderr = self.run_command(cmd)

        if returncode == 0:
            self.deleted_resources.append(f"{resource_type}/{name}" + (f" -n {namespace}" if namespace else ""))
            return True
        else:
            if stderr and self.verbose:
                self.print_error(f"Failed to delete {resource_type}/{name}: {stderr}")
            return False

    def delete_namespace_wait(self, namespace: str, timeout: int = 120) -> bool:
        """Delete namespace and wait for completion"""
        if not self.namespace_exists(namespace):
            return True

        cmd = ['kubectl', 'delete', 'namespace', namespace, f'--timeout={timeout}s']
        returncode, _, stderr = self.run_command(cmd, capture_output=True)

        if returncode == 0:
            self.deleted_resources.append(f"namespace/{namespace}")
            return True
        else:
            if self.verbose:
                self.print_error(f"Failed to delete namespace {namespace}: {stderr}")
            return False

    # ==================== Prerequisite Checks ====================

    def check_prerequisites(self) -> bool:
        """Verify required tools are installed"""
        self.print_header("Checking Prerequisites")

        tools = [
            ('kubectl', 'kubectl version --client'),
            ('helm', 'helm version')
        ]

        all_found = True
        for tool, version_cmd in tools:
            returncode, _, _ = self.run_command(version_cmd.split(), capture_output=True)
            if returncode == 0:
                self.print_success(f"{tool} is installed")
            else:
                self.print_error(f"{tool} is not installed")
                all_found = False

        # Check cluster connectivity
        returncode, _, _ = self.run_command(['kubectl', 'cluster-info'], capture_output=True)
        if returncode == 0:
            self.print_success("kubectl can connect to cluster")
        else:
            self.print_error("kubectl cannot connect to cluster")
            all_found = False

        return all_found

    # ==================== Resource Listing ====================

    def list_resources_to_delete(self) -> dict:
        """List all resources that will be deleted"""
        self.print_header("Resources to be Deleted")

        resources = {
            'ArgoCD': [],
            'Application': [],
            'Monitoring Stack': [],
            'Monitoring Resources': [],
            'Namespaces': []
        }

        # Check ArgoCD application
        if self.resource_exists('application', 'earthquake-app', 'argocd'):
            resources['ArgoCD'].append("application/earthquake-app -n argocd")

        # Check application resources in default namespace
        returncode, stdout, _ = self.run_command([
            'kubectl', 'get', 'all,configmap,secret,pvc,serviceaccount,cronjob,servicemonitor',
            '-l', 'app.kubernetes.io/instance=earthquake-app',
            '-n', 'default',
            '-o', 'name'
        ])
        if returncode == 0 and stdout.strip():
            resources['Application'].extend(stdout.strip().split('\n'))

        # Check Helm release
        if self.helm_release_exists('kube-prometheus-stack', 'monitoring'):
            resources['Monitoring Stack'].append("Helm release: kube-prometheus-stack")

        # Check monitoring resources
        monitoring_resources = [
            ('servicemonitor', 'quakewatch-app', 'default'),
            ('prometheusrule', 'quakewatch-alerts', 'monitoring'),
            ('configmap', 'quakewatch-dashboard', 'monitoring')
        ]
        for res_type, name, ns in monitoring_resources:
            if self.resource_exists(res_type, name, ns):
                resources['Monitoring Resources'].append(f"{res_type}/{name} -n {ns}")

        # Check namespaces
        for ns in ['argocd', 'monitoring']:
            if self.namespace_exists(ns):
                resources['Namespaces'].append(f"namespace/{ns}")

        # Print summary
        total = 0
        for category, items in resources.items():
            if items:
                print(f"{Colors.BOLD}{category}:{Colors.RESET}")
                for item in items[:10]:  # Show first 10
                    print(f"  • {item}")
                if len(items) > 10:
                    print(f"  ... and {len(items) - 10} more")
                total += len(items)
                print()

        if total == 0:
            self.print_info("No resources found to delete")
            return resources

        print(f"{Colors.BOLD}Total resources: {total}{Colors.RESET}\n")

        return resources

    # ==================== Cleanup Operations ====================

    def kill_port_forwards(self):
        """Kill all kubectl port-forward processes"""
        self.print_header("Stopping Port-Forward Processes")

        returncode, stdout, _ = self.run_command(['pgrep', '-f', 'kubectl port-forward'], capture_output=True)

        if returncode == 0 and stdout.strip():
            pids = stdout.strip().split('\n')
            self.print_info(f"Found {len(pids)} port-forward process(es)")

            if not self.dry_run:
                self.run_command(['pkill', '-f', 'kubectl port-forward'])
                self.print_success("All port-forwards stopped")
        else:
            self.print_info("No port-forward processes running")

    def delete_argocd_application(self):
        """Delete ArgoCD application"""
        self.print_header("Removing ArgoCD Application")

        if self.resource_exists('application', 'earthquake-app', 'argocd'):
            self.print_info("Deleting ArgoCD application 'earthquake-app'...")
            if self.delete_resource('application', 'earthquake-app', 'argocd'):
                self.print_success("ArgoCD application deleted")
                if not self.dry_run:
                    time.sleep(3)  # Brief pause for finalizers
        else:
            self.print_info("ArgoCD application not found")

    def delete_application_resources(self):
        """Delete application resources in default namespace"""
        self.print_header("Removing Application Resources")

        # Delete by label selector
        cmd = [
            'kubectl', 'delete',
            'all,configmap,secret,pvc,serviceaccount,cronjob,servicemonitor',
            '-l', 'app.kubernetes.io/instance=earthquake-app',
            '-n', 'default',
            '--ignore-not-found=true'
        ]

        returncode, stdout, _ = self.run_command(cmd)

        if returncode == 0:
            self.print_success("Application resources deleted")
            if stdout and self.verbose:
                print(stdout)
        else:
            self.print_warning("Some application resources may not have been deleted")

        # Also delete standalone ServiceMonitor
        self.delete_resource('servicemonitor', 'quakewatch-app', 'default')

    def delete_monitoring_resources(self):
        """Delete standalone monitoring resources"""
        self.print_header("Removing Monitoring Resources")

        # Delete using kubectl if files exist
        resources = [
            ('monitoring/standalone/servicemonitor.yaml', 'ServiceMonitor'),
            ('monitoring/standalone/prometheus-alerts.yaml', 'PrometheusRule'),
            ('monitoring/standalone/grafana-dashboard.yaml', 'Grafana Dashboard')
        ]

        import os
        for file_path, description in resources:
            if os.path.exists(file_path):
                returncode, _, _ = self.run_command(['kubectl', 'delete', '-f', file_path, '--ignore-not-found=true'])
                if returncode == 0:
                    self.print_success(f"{description} deleted")
            else:
                # Try deleting by resource name
                if 'servicemonitor' in file_path:
                    self.delete_resource('servicemonitor', 'quakewatch-app', 'default')
                elif 'prometheus-alerts' in file_path:
                    self.delete_resource('prometheusrule', 'quakewatch-alerts', 'monitoring')
                elif 'grafana-dashboard' in file_path:
                    self.delete_resource('configmap', 'quakewatch-dashboard', 'monitoring')

    def delete_monitoring_stack(self):
        """Delete Prometheus & Grafana Helm release"""
        self.print_header("Removing Prometheus & Grafana Stack")

        if self.helm_release_exists('kube-prometheus-stack', 'monitoring'):
            self.print_info("Uninstalling kube-prometheus-stack Helm release...")

            cmd = ['helm', 'uninstall', 'kube-prometheus-stack', '-n', 'monitoring']
            returncode, _, stderr = self.run_command(cmd)

            if returncode == 0:
                self.print_success("Helm release uninstalled")
                self.deleted_resources.append("helm-release/kube-prometheus-stack")
            else:
                self.print_error(f"Failed to uninstall Helm release: {stderr}")
        else:
            self.print_info("kube-prometheus-stack not installed")

        # Delete any remaining PVCs
        if self.namespace_exists('monitoring'):
            self.print_info("Cleaning up PVCs in monitoring namespace...")
            self.run_command(['kubectl', 'delete', 'pvc', '--all', '-n', 'monitoring', '--ignore-not-found=true'])

    def delete_namespaces(self):
        """Delete ArgoCD and monitoring namespaces"""
        self.print_header("Removing Namespaces")

        for namespace in ['argocd', 'monitoring']:
            if self.namespace_exists(namespace):
                self.print_info(f"Deleting namespace '{namespace}' (this may take a moment)...")
                if self.delete_namespace_wait(namespace, timeout=120):
                    self.print_success(f"Namespace '{namespace}' deleted")
                else:
                    self.print_warning(f"Namespace '{namespace}' deletion timed out (may still be deleting in background)")
            else:
                self.print_info(f"Namespace '{namespace}' not found")

    # ==================== Main Cleanup Flow ====================

    def run(self):
        """Execute cleanup"""
        try:
            # Header
            self.print_header("QuakeWatch Cleanup Script")

            if self.dry_run:
                self.print_warning("DRY-RUN MODE: No resources will be deleted")
                print()

            # Check prerequisites
            if not self.check_prerequisites():
                self.print_error("Prerequisites check failed")
                sys.exit(1)

            # List resources
            resources = self.list_resources_to_delete()

            # If no resources, exit
            if all(len(v) == 0 for v in resources.values()):
                self.print_success("Nothing to clean up!")
                return

            # Confirm
            if not self.dry_run:
                print(f"{Colors.YELLOW}⚠️  This will DELETE all resources listed above{Colors.RESET}")
                print(f"{Colors.GREEN}✅ Resources NOT deleted:{Colors.RESET}")
                print("  • k3s service (will keep running)")
                print("  • Prometheus Operator CRDs (shared cluster resources)")
                print("  • metrics-server (may be used by other apps)")
                print("  • kubectl config")
                print("  • Helm repositories")
                print()

                if not self.confirm_action(f"{Colors.BOLD}Proceed with cleanup?{Colors.RESET}", default=False):
                    self.print_info("Cleanup cancelled")
                    return

            start_time = time.time()

            # Execute cleanup in order
            self.kill_port_forwards()
            self.delete_argocd_application()
            self.delete_application_resources()
            self.delete_monitoring_resources()
            self.delete_monitoring_stack()
            self.delete_namespaces()

            elapsed = time.time() - start_time

            # Summary
            self.print_header("Cleanup Complete")

            if self.dry_run:
                self.print_info(f"DRY-RUN completed in {elapsed:.1f}s")
                self.print_info("Run without --dry-run to actually delete resources")
            else:
                self.print_success(f"Cleanup completed in {elapsed:.1f}s")
                self.print_info(f"Deleted {len(self.deleted_resources)} resource(s)")

                if self.verbose and self.deleted_resources:
                    print(f"\n{Colors.BOLD}Deleted resources:{Colors.RESET}")
                    for resource in self.deleted_resources:
                        print(f"  • {resource}")

            print()
            self.print_info("k3s is still running. To redeploy: ./build-deploy.sh")
            self.print_info("To stop k3s: sudo systemctl stop k3s")

        except KeyboardInterrupt:
            print()
            self.print_warning("Cleanup interrupted by user")
            sys.exit(1)
        except Exception as e:
            self.print_error(f"Unexpected error: {e}")
            if self.verbose:
                import traceback
                traceback.print_exc()
            sys.exit(1)


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description='QuakeWatch Cleanup Script - Removes resources deployed by build-deploy.sh',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument('--all', action='store_true',
                        help='Skip all confirmation prompts')
    parser.add_argument('--dry-run', action='store_true',
                        help='Show what would be deleted without actually deleting')
    parser.add_argument('--verbose', action='store_true',
                        help='Show detailed output including all commands')

    args = parser.parse_args()

    cleanup = QuakeWatchCleanup(args)
    cleanup.run()


if __name__ == "__main__":
    main()
